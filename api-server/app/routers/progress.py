from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import cast, Date, distinct, func, select

from app.core.dependencies import CurrentUser, DB
from app.models.progress import PracticeSession, Progress
from app.models.song import Song
from app.schemas.progress import (
    DailyPracticeResponse,
    PracticeSessionCreate,
    PracticeSessionResponse,
    ProgressResponse,
    UserStatsResponse,
)

router = APIRouter(prefix="/progress", tags=["progress"])


@router.get("", response_model=list[ProgressResponse])
async def list_progress(current_user: CurrentUser, db: DB):
    result = await db.execute(
        select(Progress)
        .where(Progress.user_id == current_user.id)
        .order_by(Progress.last_practiced_at.desc())
    )
    return list(result.scalars().all())


@router.get("/stats", response_model=UserStatsResponse)
async def get_stats(current_user: CurrentUser, db: DB):
    uid = current_user.id

    total_songs = (
        await db.execute(
            select(func.count()).select_from(Progress).where(Progress.user_id == uid)
        )
    ).scalar_one()

    total_seconds = (
        await db.execute(
            select(func.sum(Progress.total_practice_seconds)).where(Progress.user_id == uid)
        )
    ).scalar_one() or 0

    songs_completed = (
        await db.execute(
            select(func.count())
            .select_from(Progress)
            .where(Progress.user_id == uid, Progress.is_completed == True)  # noqa: E712
        )
    ).scalar_one()

    avg_score = (
        await db.execute(
            select(func.avg(Progress.best_score)).where(
                Progress.user_id == uid, Progress.best_score.is_not(None)
            )
        )
    ).scalar_one()

    # Streak: count consecutive days (from today backwards) that had at least one session
    practice_dates_result = await db.execute(
        select(distinct(cast(PracticeSession.ended_at, Date)))
        .where(PracticeSession.user_id == uid)
        .order_by(cast(PracticeSession.ended_at, Date).desc())
    )
    practice_dates: list[date] = [row[0] for row in practice_dates_result.all()]

    streak = 0
    today = datetime.now(timezone.utc).date()
    for i, d in enumerate(practice_dates):
        if d == today - timedelta(days=i):
            streak += 1
        else:
            break

    return UserStatsResponse(
        total_songs_practiced=total_songs,
        total_practice_seconds=int(total_seconds),
        songs_completed=songs_completed,
        average_score=float(avg_score) if avg_score is not None else None,
        current_streak_days=streak,
    )


@router.get("/weekly", response_model=list[DailyPracticeResponse])
async def weekly_stats(current_user: CurrentUser, db: DB):
    """过去 7 天每天的练习汇总（无数据的天不返回，由客户端补零）。"""
    uid = current_user.id
    cutoff = datetime.now(timezone.utc) - timedelta(days=6)
    day_start = cutoff.replace(hour=0, minute=0, second=0, microsecond=0)

    day_col = cast(PracticeSession.started_at, Date)

    rows = await db.execute(
        select(
            day_col.label("day"),
            func.sum(PracticeSession.duration_seconds).label("total_seconds"),
            func.avg(PracticeSession.score).label("avg_score"),
            func.count().label("session_count"),
        )
        .where(
            PracticeSession.user_id == uid,
            PracticeSession.started_at >= day_start,
        )
        .group_by(day_col)
        .order_by(day_col)
    )

    return [
        DailyPracticeResponse(
            # 将 date 转回 UTC midnight datetime，保证 ISO8601 带时区
            date=datetime(row.day.year, row.day.month, row.day.day, tzinfo=timezone.utc),
            total_seconds=int(row.total_seconds),
            avg_score=float(row.avg_score) if row.avg_score is not None else None,
            session_count=int(row.session_count),
        )
        for row in rows.all()
    ]


@router.get("/{song_id}", response_model=ProgressResponse)
async def get_song_progress(song_id: str, current_user: CurrentUser, db: DB):
    result = await db.execute(
        select(Progress).where(
            Progress.user_id == current_user.id,
            Progress.song_id == song_id,
        )
    )
    prog = result.scalar_one_or_none()
    if not prog:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No progress found for this song")
    return prog


@router.post("/sessions", response_model=PracticeSessionResponse, status_code=status.HTTP_201_CREATED)
async def record_session(body: PracticeSessionCreate, current_user: CurrentUser, db: DB):
    song = await db.get(Song, body.song_id)
    if not song:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Song not found")

    # Upsert the progress summary row
    result = await db.execute(
        select(Progress).where(
            Progress.user_id == current_user.id,
            Progress.song_id == body.song_id,
        )
    )
    prog = result.scalar_one_or_none()
    if not prog:
        prog = Progress(user_id=current_user.id, song_id=body.song_id)
        db.add(prog)
        await db.flush()

    session = PracticeSession(
        user_id=current_user.id,
        song_id=body.song_id,
        progress_id=prog.id,
        score=body.score,
        duration_seconds=body.duration_seconds,
        notes_hit=body.notes_hit,
        notes_total=body.notes_total,
        started_at=body.started_at,
    )
    db.add(session)
    await db.flush()

    # Update aggregates
    prog.practice_count += 1
    prog.total_practice_seconds += body.duration_seconds
    prog.last_practiced_at = session.ended_at
    if prog.best_score is None or body.score > prog.best_score:
        prog.best_score = body.score
    if body.score >= 95:
        prog.is_completed = True

    return session
