import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class PracticeSessionCreate(BaseModel):
    song_id: uuid.UUID
    score: float = Field(ge=0, le=100)
    duration_seconds: int = Field(gt=0)
    notes_hit: int | None = Field(default=None, ge=0)
    notes_total: int | None = Field(default=None, ge=0)
    started_at: datetime


class PracticeSessionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    song_id: uuid.UUID
    score: float
    duration_seconds: int
    notes_hit: int | None
    notes_total: int | None
    started_at: datetime
    ended_at: datetime


class ProgressResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    song_id: uuid.UUID
    practice_count: int
    best_score: float | None
    total_practice_seconds: int
    is_completed: bool
    last_practiced_at: datetime | None
    updated_at: datetime


class UserStatsResponse(BaseModel):
    total_songs_practiced: int
    total_practice_seconds: int
    songs_completed: int
    average_score: float | None
    current_streak_days: int


class DailyPracticeResponse(BaseModel):
    date: datetime          # midnight UTC of that day (ISO8601 datetime)
    total_seconds: int
    avg_score: float | None
    session_count: int
