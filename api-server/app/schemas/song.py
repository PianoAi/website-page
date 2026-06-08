import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class SongTranslationUpsert(BaseModel):
    """PUT /admin/songs/{id}/translations/{locale}"""
    title: str


class SongUpdate(BaseModel):
    """PATCH /admin/songs/{id} — 只传需要修改的字段。"""
    composer: str | None = None
    difficulty: str | None = None
    genre: str | None = None
    bpm: int | None = None
    is_premium: bool | None = None
    description: str | None = None


class SongResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    localized_title: str | None = None   # 由 Accept-Language 决定，服务端选好后返回
    composer: str | None
    arranger: str | None
    difficulty: str
    genre: str
    duration_seconds: int | None
    bpm: int | None
    time_signature: str | None
    key_signature: str | None
    is_premium: bool
    description: str | None
    created_at: datetime


class SongFilesResponse(BaseModel):
    midi_url: str | None
    sheet_pdf_url: str | None
    thumbnail_url: str | None
    expires_in: int = 3600


class SongListResponse(BaseModel):
    items: list[SongResponse]
    total: int
    page: int
    page_size: int
    has_more: bool
