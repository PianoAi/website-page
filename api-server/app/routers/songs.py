from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy import case, func, or_, select

from app.core.dependencies import CurrentUser, DB
from app.core.storage import get_presigned_download_url
from app.models.song import Song, SongTranslation
from app.models.subscription import Subscription
from app.schemas.song import SongFilesResponse, SongListResponse, SongResponse

router = APIRouter(prefix="/songs", tags=["songs"])


# ── Accept-Language 解析 ───────────────────────────────────────────────────────

def _parse_accept_language(header: str | None) -> list[str]:
    """
    将 Accept-Language 头解析为按优先级排序的 locale 列表。
    例如 "zh-Hans,zh;q=0.9,en;q=0.8,ja;q=0.7" → ["zh-Hans", "zh", "ja"]
    英文是 fallback（原始 title），不加入列表。
    同时展开语言前缀：["zh-Hans"] → ["zh-Hans", "zh"]
    """
    if not header:
        return []

    pairs: list[tuple[float, str]] = []
    for part in header.split(","):
        part = part.strip()
        if ";q=" in part:
            locale, q_str = part.split(";q=", 1)
            q = float(q_str)
        else:
            locale, q = part, 1.0
        locale = locale.strip()
        if locale.startswith("en"):   # 英文 = 原始标题，无需查翻译表
            continue
        pairs.append((q, locale))

    pairs.sort(key=lambda x: -x[0])

    seen: set[str] = set()
    result: list[str] = []
    for _, locale in pairs:
        if locale not in seen:
            result.append(locale)
            seen.add(locale)
        # 展开所有前缀层级：zh-Hans-US → zh-Hans → zh
        parts = locale.split("-")
        for i in range(len(parts) - 1, 0, -1):
            prefix = "-".join(parts[:i])
            if prefix not in seen:
                result.append(prefix)
                seen.add(prefix)

    return result


def _localized_title_subquery(locales: list[str]):
    """
    返回一个标量子查询：对于当前 Song 行，按 locales 优先级取最佳翻译标题。
    若无匹配翻译则返回 NULL（由 iOS 端 fallback 到 song.title）。
    """
    if not locales:
        return None

    priority = case(
        *[(SongTranslation.locale == loc, i) for i, loc in enumerate(locales)],
        else_=999,
    )

    return (
        select(SongTranslation.title)
        .where(
            SongTranslation.song_id == Song.id,
            SongTranslation.locale.in_(locales),
        )
        .order_by(priority)
        .limit(1)
        .correlate(Song)
        .scalar_subquery()
        .label("localized_title")
    )


def _to_response(song: Song, localized_title: str | None) -> SongResponse:
    return SongResponse(
        id=song.id,
        title=song.title,
        localized_title=localized_title,
        composer=song.composer,
        arranger=song.arranger,
        difficulty=song.difficulty,
        genre=song.genre,
        duration_seconds=song.duration_seconds,
        bpm=song.bpm,
        time_signature=song.time_signature,
        key_signature=song.key_signature,
        is_premium=song.is_premium,
        description=song.description,
        created_at=song.created_at,
    )


# ── 端点 ──────────────────────────────────────────────────────────────────────

@router.get("", response_model=SongListResponse)
async def list_songs(
    request: Request,
    db: DB,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    difficulty: str | None = Query(None),
    genre: str | None = Query(None),
    search: str | None = Query(None),
    is_premium: bool | None = Query(None),
):
    locales = _parse_accept_language(request.headers.get("accept-language"))
    trans_subq = _localized_title_subquery(locales)

    filters = [Song.is_published == True]  # noqa: E712
    if difficulty:
        filters.append(Song.difficulty == difficulty)
    if genre:
        filters.append(Song.genre == genre)
    if is_premium is not None:
        filters.append(Song.is_premium == is_premium)
    if search:
        filters.append(
            or_(Song.title.ilike(f"%{search}%"), Song.composer.ilike(f"%{search}%"))
        )

    total = (
        await db.execute(select(func.count()).select_from(Song).where(*filters))
    ).scalar_one()

    if trans_subq is not None:
        stmt = (
            select(Song, trans_subq)
            .where(*filters)
            .order_by(Song.created_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        rows = (await db.execute(stmt)).all()
        items = [_to_response(song, loc_title) for song, loc_title in rows]
    else:
        songs = (
            await db.execute(
                select(Song)
                .where(*filters)
                .order_by(Song.created_at.desc())
                .offset((page - 1) * page_size)
                .limit(page_size)
            )
        ).scalars().all()
        items = [_to_response(s, None) for s in songs]

    return SongListResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        has_more=(page * page_size) < total,
    )


@router.get("/{song_id}", response_model=SongResponse)
async def get_song(song_id: str, request: Request, db: DB):
    locales = _parse_accept_language(request.headers.get("accept-language"))
    trans_subq = _localized_title_subquery(locales)

    if trans_subq is not None:
        row = (
            await db.execute(
                select(Song, trans_subq)
                .where(Song.id == song_id, Song.is_published == True)  # noqa: E712
            )
        ).one_or_none()
        if not row:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Song not found")
        return _to_response(row[0], row[1])
    else:
        song = (
            await db.execute(
                select(Song).where(Song.id == song_id, Song.is_published == True)  # noqa: E712
            )
        ).scalar_one_or_none()
        if not song:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Song not found")
        return _to_response(song, None)


@router.get("/{song_id}/files", response_model=SongFilesResponse)
async def get_song_files(song_id: str, current_user: CurrentUser, db: DB):
    """Returns short-lived presigned URLs for MIDI and sheet PDF."""
    result = await db.execute(
        select(Song).where(Song.id == song_id, Song.is_published == True)  # noqa: E712
    )
    song = result.scalar_one_or_none()
    if not song:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Song not found")

    if song.is_premium:
        now = datetime.now(timezone.utc)
        sub = (
            await db.execute(
                select(Subscription).where(
                    Subscription.user_id == current_user.id,
                    Subscription.is_active == True,  # noqa: E712
                    Subscription.expires_at > now,
                )
            )
        ).scalar_one_or_none()
        if not sub:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Premium subscription required")

    return SongFilesResponse(
        midi_url=get_presigned_download_url(song.midi_s3_key) if song.midi_s3_key else None,
        sheet_pdf_url=(
            get_presigned_download_url(song.sheet_pdf_s3_key) if song.sheet_pdf_s3_key else None
        ),
        thumbnail_url=(
            get_presigned_download_url(song.thumbnail_s3_key) if song.thumbnail_s3_key else None
        ),
    )
