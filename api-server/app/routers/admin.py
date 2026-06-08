import uuid
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, Security, UploadFile, status
from fastapi.security import APIKeyHeader
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.storage import delete_object, object_exists, upload_bytes
from app.models.song import Song, SongTranslation
from app.schemas.song import SongResponse, SongTranslationUpsert, SongUpdate

router = APIRouter(prefix="/admin", tags=["admin"])

# ── 鉴权 ──────────────────────────────────────────────────────────────────────

_api_key_header = APIKeyHeader(name="X-Admin-Key", auto_error=False)


def require_admin(key: Annotated[str | None, Security(_api_key_header)]) -> None:
    if not settings.admin_api_key or key != settings.admin_api_key:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid admin key")


AdminAuth = Annotated[None, Depends(require_admin)]
DB = Annotated[AsyncSession, Depends(get_db)]

# ── 工具 ──────────────────────────────────────────────────────────────────────

_MIDI_MAGIC = b"MThd"
_VALID_CONTENT_TYPES = {"audio/midi", "audio/x-midi", "audio/mid", "application/octet-stream"}


def _midi_s3_key(song_id: uuid.UUID) -> str:
    return f"midi/{song_id}.mid"


def _validate_midi(data: bytes) -> None:
    if not data.startswith(_MIDI_MAGIC):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                            detail="File is not a valid MIDI (missing MThd header)")


# ── 端点 ──────────────────────────────────────────────────────────────────────

@router.get("/songs", response_model=list[SongResponse])
async def list_songs(_: AdminAuth, db: DB):
    """列出所有曲目（含未发布）。"""
    result = await db.execute(select(Song).order_by(Song.created_at.desc()))
    return result.scalars().all()


@router.post("/songs", response_model=SongResponse, status_code=status.HTTP_201_CREATED)
async def create_song(
    _: AdminAuth,
    db: DB,
    title: str = Form(...),
    composer: str = Form(""),
    difficulty: str = Form("intermediate"),
    genre: str = Form("classical"),
    is_premium: bool = Form(False),
    description: str = Form(""),
    arranger: str = Form(""),
    bpm: int | None = Form(None),
    midi_file: UploadFile = File(...),
):
    """
    创建一首曲目并上传 MIDI 文件。
    可在 /docs 里直接用 multipart/form-data 测试。
    """
    data = await midi_file.read()
    _validate_midi(data)

    song = Song(
        title=title,
        composer=composer or None,
        arranger=arranger or None,
        difficulty=difficulty,
        genre=genre,
        bpm=bpm,
        is_premium=is_premium,
        description=description or None,
        is_published=False,  # 上传后默认不发布，确认无误再发布
    )
    db.add(song)
    await db.flush()  # 获取 song.id

    s3_key = _midi_s3_key(song.id)
    upload_bytes(s3_key, data, "audio/midi")
    song.midi_s3_key = s3_key

    return song


@router.patch("/songs/{song_id}", response_model=SongResponse)
async def update_song(_: AdminAuth, song_id: uuid.UUID, body: SongUpdate, db: DB):
    """更新曲目元数据（只传需要修改的字段）。"""
    song = await db.get(Song, song_id)
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(song, field, value)
    return song


@router.patch("/songs/{song_id}/publish", response_model=SongResponse)
async def publish_song(_: AdminAuth, song_id: uuid.UUID, db: DB):
    """发布曲目（is_published = True）。"""
    song = await db.get(Song, song_id)
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")
    song.is_published = True
    return song


@router.patch("/songs/{song_id}/unpublish", response_model=SongResponse)
async def unpublish_song(_: AdminAuth, song_id: uuid.UUID, db: DB):
    """下架曲目。"""
    song = await db.get(Song, song_id)
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")
    song.is_published = False
    return song


@router.delete("/songs/{song_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_song(_: AdminAuth, song_id: uuid.UUID, db: DB):
    """删除曲目及对应 MIDI 文件。"""
    song = await db.get(Song, song_id)
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")
    if song.midi_s3_key:
        delete_object(song.midi_s3_key)
    await db.delete(song)


@router.get("/songs/{song_id}/translations")
async def list_translations(_: AdminAuth, song_id: uuid.UUID, db: DB):
    """列出某首歌的所有已有翻译。"""
    rows = (
        await db.execute(
            select(SongTranslation).where(SongTranslation.song_id == song_id)
        )
    ).scalars().all()
    return [{"locale": r.locale, "title": r.title} for r in rows]


@router.put("/songs/{song_id}/translations/{locale}", status_code=status.HTTP_200_OK)
async def upsert_translation(
    _: AdminAuth, song_id: uuid.UUID, locale: str, body: SongTranslationUpsert, db: DB
):
    """新增或更新某一语言的翻译标题。"""
    existing = await db.get(SongTranslation, (song_id, locale))
    if existing:
        existing.title = body.title
    else:
        db.add(SongTranslation(song_id=song_id, locale=locale, title=body.title))
    return {"song_id": song_id, "locale": locale, "title": body.title}


@router.delete("/songs/{song_id}/translations/{locale}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_translation(_: AdminAuth, song_id: uuid.UUID, locale: str, db: DB):
    """删除某一语言的翻译。"""
    existing = await db.get(SongTranslation, (song_id, locale))
    if existing:
        await db.delete(existing)


@router.post("/songs/import-catalog", status_code=status.HTTP_200_OK)
async def import_catalog(
    _: AdminAuth,
    db: DB,
    catalog: list[dict],
):
    """
    从 catalog.json 批量导入曲目并上传 MIDI 到存储桶。

    请求体直接贴 catalog.json 的内容（JSON 数组）。
    服务器从 local_path 读取本地 MIDI 文件并上传，因此只在本机开发时使用。

    返回: { ok: int, skipped: int, errors: list[str] }
    """
    ok = skipped = 0
    errors: list[str] = []

    for entry in catalog:
        local_path = entry.get("local_path", "")
        title = entry.get("title", "").strip()

        if not title:
            errors.append(f"Skipped entry with no title: {entry}")
            skipped += 1
            continue

        midi_file = Path(local_path)
        if not midi_file.exists():
            errors.append(f"MIDI not found: {local_path}")
            skipped += 1
            continue

        midi_data = midi_file.read_bytes()
        if not midi_data.startswith(_MIDI_MAGIC):
            errors.append(f"Invalid MIDI: {local_path}")
            skipped += 1
            continue

        # 用 midi_url 去重 —— 每个乐章 URL 唯一，不会误判同名多乐章
        source_url = entry.get("midi_url", "")
        composer = entry.get("composer", "")

        existing_song: Song | None = None
        if source_url:
            result = await db.execute(
                select(Song).where(Song.source_url == source_url).limit(1)
            )
            existing_song = result.scalar_one_or_none()

        if existing_song:
            # DB 有记录 —— 检查 S3 文件是否还在
            if existing_song.midi_s3_key and object_exists(existing_song.midi_s3_key):
                skipped += 1
                continue
            # 文件被删了，重新上传到原来的 key
            upload_bytes(existing_song.midi_s3_key, midi_data, "audio/midi")
            ok += 1
            continue

        # 全新记录：建 DB 条目 + 上传 S3
        song = Song(
            title=title,
            composer=composer or None,
            difficulty=entry.get("difficulty") or "intermediate",
            genre=_map_style(entry.get("style", "")),
            description=entry.get("opus") or None,
            source_url=source_url or None,
            is_premium=False,
            is_published=True,
        )
        db.add(song)
        await db.flush()

        s3_key = _midi_s3_key(song.id)
        upload_bytes(s3_key, midi_data, "audio/midi")
        song.midi_s3_key = s3_key

        ok += 1

    return {"ok": ok, "skipped": skipped, "errors": errors[:20]}


# ── 辅助 ──────────────────────────────────────────────────────────────────────

_STYLE_TO_GENRE: dict[str, str] = {
    "baroque":       "classical",
    "classical":     "classical",
    "romantic":      "classical",
    "modern":        "modern",
    "avant-garde":   "modern",
    "folk":          "folk",
    "jazz":          "jazz",
    "march":         "classical",
    "hymn":          "folk",
    "technique":     "classical",
    "popular":       "pop",
    "dance":         "pop",
}


def _map_style(style: str) -> str:
    return _STYLE_TO_GENRE.get(style.lower().split("/")[0].strip(), "classical")
