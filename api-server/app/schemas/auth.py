import uuid
from datetime import datetime

from pydantic import BaseModel, EmailStr, Field, field_validator


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(min_length=1, max_length=100)

    @field_validator("password")
    @classmethod
    def password_complexity(cls, v: str) -> str:
        errors = []
        if not any(c.isupper() for c in v):
            errors.append("至少包含一个大写字母")
        if not any(c.islower() for c in v):
            errors.append("至少包含一个小写字母")
        if not any(c.isdigit() for c in v):
            errors.append("至少包含一个数字")
        if errors:
            raise ValueError("密码不符合要求：" + "；".join(errors))
        return v


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class AppleAuthRequest(BaseModel):
    identity_token: str
    display_name: str | None = None


class GoogleAuthRequest(BaseModel):
    id_token: str
    display_name: str | None = None


class PhoneOtpRequest(BaseModel):
    phone_number: str = Field(pattern=r"^\+[1-9]\d{7,14}$")  # E.164 format


class PhoneVerifyRequest(BaseModel):
    phone_number: str = Field(pattern=r"^\+[1-9]\d{7,14}$")
    otp: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    session_id: str           # RefreshToken.id，供客户端标记当前会话
    token_type: str = "bearer"


class SessionResponse(BaseModel):
    id: uuid.UUID
    device_name: str | None
    platform: str | None
    last_used_at: datetime | None
    created_at: datetime
    is_current: bool = False


class PasswordResetRequest(BaseModel):
    email: EmailStr


class PasswordResetConfirm(BaseModel):
    token: str
    new_password: str = Field(min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def password_complexity(cls, v: str) -> str:
        errors = []
        if not any(c.isupper() for c in v):
            errors.append("至少包含一个大写字母")
        if not any(c.islower() for c in v):
            errors.append("至少包含一个小写字母")
        if not any(c.isdigit() for c in v):
            errors.append("至少包含一个数字")
        if errors:
            raise ValueError("密码不符合要求：" + "；".join(errors))
        return v


class EmailVerifyRequest(BaseModel):
    token: str
