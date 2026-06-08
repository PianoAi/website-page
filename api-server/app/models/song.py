import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, SmallInteger, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Song(Base):
    __tablename__ = "songs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(255), index=True)
    composer: Mapped[str | None] = mapped_column(String(255), nullable=True)
    arranger: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # difficulty: "beginner" | "intermediate" | "advanced"
    difficulty: Mapped[str] = mapped_column(String(20), index=True)
    # genre: "classical" | "pop" | "jazz" | "folk" | "game" | "film" | ...
    genre: Mapped[str] = mapped_column(String(50), index=True)

    duration_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    bpm: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    time_signature: Mapped[str | None] = mapped_column(String(10), nullable=True)
    key_signature: Mapped[str | None] = mapped_column(String(15), nullable=True)

    # S3/R2 object keys — presigned URLs generated on demand
    midi_s3_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    sheet_pdf_s3_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    thumbnail_s3_key: Mapped[str | None] = mapped_column(String(500), nullable=True)

    # 来源 URL（如 Mutopia MIDI 链接），用于去重和溯源
    source_url: Mapped[str | None] = mapped_column(String(1000), unique=True, nullable=True)

    is_premium: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    is_published: Mapped[bool] = mapped_column(Boolean, default=True, index=True)

    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, onupdate=_now)


class SongTranslation(Base):
    """Per-locale title translations for songs."""
    __tablename__ = "song_translations"

    song_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("songs.id", ondelete="CASCADE"),
        primary_key=True,
    )
    locale: Mapped[str] = mapped_column(String(10), primary_key=True, index=True)  # e.g. "zh-Hans", "ja", "ko"
    title: Mapped[str] = mapped_column(Text, nullable=False)
