import secrets
from datetime import datetime, timedelta, timezone

import httpx
import jwt
from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import (
    create_access_token,
    create_refresh_token_pair,
    generate_otp,
    hash_password,
    hash_token,
    verify_password,
)
from app.models.user import (
    AuthProvider, EmailVerificationToken, PasswordResetToken, PhoneOtp, RefreshToken, User,
)
from app.schemas.auth import TokenResponse


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


async def _issue_tokens(
    user: User,
    db: AsyncSession,
    device_name: str | None = None,
    platform: str | None = None,
) -> TokenResponse:
    raw_refresh, hashed_refresh = create_refresh_token_pair()
    expires_at = datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_expire_days)

    now = datetime.now(timezone.utc)
    session = RefreshToken(
        user_id=user.id,
        token_hash=hashed_refresh,
        expires_at=expires_at,
        device_name=device_name,
        platform=platform,
        last_used_at=now,
    )
    db.add(session)
    await db.flush()

    return TokenResponse(
        access_token=create_access_token(str(user.id)),
        refresh_token=raw_refresh,
        session_id=str(session.id),
    )


async def _lookup_location(ip: str | None) -> str | None:
    """免费 IP 地理查询（ip-api.com），失败时静默返回 None。"""
    if not ip or ip in ("127.0.0.1", "::1", "testclient"):
        return None
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            r = await client.get(
                f"http://ip-api.com/json/{ip}",
                params={"fields": "status,city,country", "lang": "zh-CN"},
            )
            data = r.json()
            if data.get("status") == "success":
                city    = data.get("city", "")
                country = data.get("country", "")
                return f"{city}, {country}".strip(", ") or None
    except Exception:
        pass
    return None


async def _find_provider(
    provider: str, provider_user_id: str, db: AsyncSession
) -> AuthProvider | None:
    result = await db.execute(
        select(AuthProvider).where(
            AuthProvider.provider == provider,
            AuthProvider.provider_user_id == provider_user_id,
        )
    )
    return result.scalar_one_or_none()


async def _get_or_create_oauth_user(
    provider: str, provider_user_id: str, display_name: str | None, db: AsyncSession
) -> User:
    existing = await _find_provider(provider, provider_user_id, db)
    if existing:
        result = await db.execute(select(User).where(User.id == existing.user_id))
        return result.scalar_one()

    user = User(display_name=display_name or "User")
    db.add(user)
    await db.flush()
    db.add(AuthProvider(user_id=user.id, provider=provider, provider_user_id=provider_user_id))
    return user


# ---------------------------------------------------------------------------
# Email / password
# ---------------------------------------------------------------------------


async def register_email(
    email: str, password: str, display_name: str, db: AsyncSession
) -> TokenResponse:
    if await _find_provider("email", email.lower(), db):
        raise HTTPException(status.HTTP_409_CONFLICT, "Email already registered")

    user = User(display_name=display_name)
    db.add(user)
    await db.flush()

    db.add(
        AuthProvider(
            user_id=user.id,
            provider="email",
            provider_user_id=email.lower(),
            hashed_password=hash_password(password),
        )
    )
    tokens = await _issue_tokens(user, db)

    # 发送邮箱验证邮件（异步，失败不影响注册）
    try:
        await _send_email_verification(user.id, email.lower(), db)
    except Exception:
        pass  # 邮件失败不阻断注册流程

    return tokens


_MAX_FAILED_ATTEMPTS = 5
_LOCKOUT_MINUTES     = 15


async def _persist_login_failure(
    provider_id, new_count: int, locked_until
) -> None:
    """独立 session 提交失败计数，确保主 session rollback 时不影响此更新。"""
    from sqlalchemy import update as sql_update
    from app.core.database import AsyncSessionLocal

    async with AsyncSessionLocal() as db:
        try:
            await db.execute(
                sql_update(AuthProvider)
                .where(AuthProvider.id == provider_id)
                .values(failed_login_count=new_count, locked_until=locked_until)
            )
            await db.commit()
        except Exception:
            await db.rollback()


async def login_email(
    email: str,
    password: str,
    db: AsyncSession,
    device_name: str | None = None,
    platform: str | None = None,
    ip: str | None = None,
) -> TokenResponse:
    provider = await _find_provider("email", email.lower(), db)
    invalid = HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid credentials")

    if not provider or not provider.hashed_password:
        raise invalid

    now = datetime.now(timezone.utc)

    # 账号锁定检查
    if provider.locked_until and provider.locked_until > now:
        remaining = int((provider.locked_until - now).total_seconds() / 60) + 1
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            f"账号已暂时锁定，请 {remaining} 分钟后重试",
        )

    if not verify_password(password, provider.hashed_password):
        # 用独立 session 提交计数（主 session 在抛出异常后会 rollback）
        new_count = (provider.failed_login_count or 0) + 1
        locked_until = None
        if new_count >= _MAX_FAILED_ATTEMPTS:
            locked_until = now + timedelta(minutes=_LOCKOUT_MINUTES)
            new_count = 0
        await _persist_login_failure(provider.id, new_count, locked_until)
        raise invalid

    # 登录成功 — 重置失败计数（主 session 正常提交）
    provider.failed_login_count = 0
    provider.locked_until = None

    result = await db.execute(
        select(User).where(User.id == provider.user_id, User.is_active == True)  # noqa: E712
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Account disabled")

    tokens = await _issue_tokens(user, db, device_name=device_name, platform=platform)

    # 新登录通知邮件（不阻断登录流程）
    try:
        from app.services.email import send_new_login_notification
        location = await _lookup_location(ip)
        await send_new_login_notification(
            to=email.lower(),
            device_name=device_name,
            platform=platform,
            ip=ip,
            location=location,
        )
    except Exception:
        pass

    return tokens


# ---------------------------------------------------------------------------
# Apple Sign In
# ---------------------------------------------------------------------------


async def auth_apple(
    identity_token: str, display_name: str | None, db: AsyncSession
) -> TokenResponse:
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get("https://appleid.apple.com/auth/keys")
            resp.raise_for_status()
            jwks = resp.json()

        header = jwt.get_unverified_header(identity_token)
        jwk = next((k for k in jwks["keys"] if k["kid"] == header["kid"]), None)
        if not jwk:
            raise ValueError("Signing key not found in Apple JWKS")

        from jwt.algorithms import RSAAlgorithm

        public_key = RSAAlgorithm.from_jwk(jwk)
        payload = jwt.decode(
            identity_token,
            public_key,
            algorithms=["RS256"],
            audience=settings.apple_app_bundle_id or None,
            options={"verify_aud": bool(settings.apple_app_bundle_id)},
        )
        apple_user_id: str = payload["sub"]
    except Exception:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid Apple identity token")

    user = await _get_or_create_oauth_user("apple", apple_user_id, display_name, db)
    return await _issue_tokens(user, db)


# ---------------------------------------------------------------------------
# Google Sign In
# ---------------------------------------------------------------------------


async def auth_google(
    id_token: str, display_name: str | None, db: AsyncSession
) -> TokenResponse:
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"id_token": id_token},
            )
            if resp.status_code != 200:
                raise ValueError("Token rejected by Google")
            data = resp.json()

        # audience 必须与 Google Client ID 匹配（配置缺失时拒绝所有 token）
        if not settings.google_client_id:
            raise ValueError("Google client_id not configured on server")
        if data.get("aud") != settings.google_client_id:
            raise ValueError("Audience mismatch")

        google_user_id: str = data["sub"]
        name = display_name or data.get("name")
    except Exception:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid Google ID token")

    user = await _get_or_create_oauth_user("google", google_user_id, name, db)
    return await _issue_tokens(user, db)


# ---------------------------------------------------------------------------
# Phone OTP
# ---------------------------------------------------------------------------


async def send_phone_otp(phone_number: str, db: AsyncSession) -> None:
    from app.services.sms import get_sms_service

    plain_otp, otp_hash = generate_otp()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)

    db.add(PhoneOtp(phone_number=phone_number, otp_hash=otp_hash, expires_at=expires_at))
    await db.flush()

    await get_sms_service().send(phone_number, f"Your PianoLearn code: {plain_otp}")


async def verify_phone_otp(
    phone_number: str, otp_plain: str, db: AsyncSession
) -> TokenResponse:
    import hashlib

    otp_hash = hashlib.sha256(otp_plain.encode()).hexdigest()
    now = datetime.now(timezone.utc)

    result = await db.execute(
        select(PhoneOtp)
        .where(
            PhoneOtp.phone_number == phone_number,
            PhoneOtp.otp_hash == otp_hash,
            PhoneOtp.is_used == False,  # noqa: E712
            PhoneOtp.expires_at > now,
        )
        .order_by(PhoneOtp.created_at.desc())
        .limit(1)
    )
    otp = result.scalar_one_or_none()
    if not otp:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired OTP")

    otp.is_used = True
    user = await _get_or_create_oauth_user("phone", phone_number, None, db)
    return await _issue_tokens(user, db)


# ---------------------------------------------------------------------------
# Token management
# ---------------------------------------------------------------------------


async def refresh_tokens(raw_refresh_token: str, db: AsyncSession) -> TokenResponse:
    token_hash = hash_token(raw_refresh_token)
    now = datetime.now(timezone.utc)

    result = await db.execute(
        select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.expires_at > now,
        )
    )
    stored = result.scalar_one_or_none()
    if not stored:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired refresh token")

    user_id      = stored.user_id
    device_name  = stored.device_name
    platform     = stored.platform

    await db.delete(stored)  # rotate — old token becomes invalid immediately
    await db.flush()

    result = await db.execute(
        select(User).where(User.id == user_id, User.is_active == True)  # noqa: E712
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User not found")

    # 继承旧会话的设备信息，发给新 token
    return await _issue_tokens(user, db, device_name=device_name, platform=platform)


# ---------------------------------------------------------------------------
# Session management
# ---------------------------------------------------------------------------

async def list_sessions(
    user_id: str, current_session_id: str | None, db: AsyncSession
) -> list:
    from app.schemas.auth import SessionResponse

    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(RefreshToken)
        .where(RefreshToken.user_id == user_id, RefreshToken.expires_at > now)
        .order_by(RefreshToken.last_used_at.desc().nullslast())
    )
    sessions = result.scalars().all()
    return [
        SessionResponse(
            id=s.id,
            device_name=s.device_name,
            platform=s.platform,
            last_used_at=s.last_used_at,
            created_at=s.created_at,
            is_current=(str(s.id) == current_session_id),
        )
        for s in sessions
    ]


async def revoke_session(session_id: str, user_id: str, db: AsyncSession) -> None:
    result = await db.execute(
        select(RefreshToken).where(
            RefreshToken.id == session_id,
            RefreshToken.user_id == user_id,
        )
    )
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Session not found")
    await db.delete(session)


async def revoke_other_sessions(
    user_id: str, current_session_id: str | None, db: AsyncSession
) -> int:
    """撤销除当前会话外的所有会话，返回撤销数量。"""
    from sqlalchemy import delete as sql_delete

    filters = [RefreshToken.user_id == user_id]
    if current_session_id:
        filters.append(RefreshToken.id != current_session_id)

    result = await db.execute(
        sql_delete(RefreshToken).where(*filters).returning(RefreshToken.id)
    )
    return len(result.all())


async def logout(raw_refresh_token: str, db: AsyncSession) -> None:
    token_hash = hash_token(raw_refresh_token)
    result = await db.execute(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    )
    stored = result.scalar_one_or_none()
    if stored:
        await db.delete(stored)


# ---------------------------------------------------------------------------
# Password reset
# ---------------------------------------------------------------------------

async def request_password_reset(email: str, db: AsyncSession) -> None:
    """始终返回成功（不泄露邮箱是否注册）。"""
    from app.services.email import send_password_reset

    provider = await _find_provider("email", email.lower(), db)
    if not provider:
        return  # silently ignore unknown email

    raw_token = secrets.token_urlsafe(32)
    token_hash = hash_token(raw_token)
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=settings.password_reset_expire_minutes
    )

    db.add(PasswordResetToken(
        user_id=provider.user_id,
        token_hash=token_hash,
        expires_at=expires_at,
    ))
    await db.flush()
    await send_password_reset(email.lower(), raw_token)


async def confirm_password_reset(token: str, new_password: str, db: AsyncSession) -> None:
    token_hash = hash_token(token)
    now = datetime.now(timezone.utc)

    result = await db.execute(
        select(PasswordResetToken).where(
            PasswordResetToken.token_hash == token_hash,
            PasswordResetToken.expires_at > now,
            PasswordResetToken.used_at.is_(None),
        )
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid or expired reset token")

    # 找到 email provider 更新密码
    result = await db.execute(
        select(AuthProvider).where(
            AuthProvider.user_id == record.user_id,
            AuthProvider.provider == "email",
        )
    )
    provider = result.scalar_one_or_none()
    if not provider:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "No email login found for this account")

    provider.hashed_password = hash_password(new_password)
    record.used_at = now

    # 可选：重置密码后吊销所有 refresh token（强制重新登录）
    await db.execute(
        select(RefreshToken).where(RefreshToken.user_id == record.user_id)
    )
    # 删除该用户所有 refresh token
    from sqlalchemy import delete as sql_delete
    await db.execute(
        sql_delete(RefreshToken).where(RefreshToken.user_id == record.user_id)
    )


# ---------------------------------------------------------------------------
# Email verification
# ---------------------------------------------------------------------------

async def _send_email_verification(user_id, email: str, db: AsyncSession) -> None:
    from app.services.email import send_email_verification

    raw_token = secrets.token_urlsafe(32)
    token_hash = hash_token(raw_token)
    expires_at = datetime.now(timezone.utc) + timedelta(
        hours=settings.email_verify_expire_hours
    )

    db.add(EmailVerificationToken(
        user_id=user_id,
        email=email,
        token_hash=token_hash,
        expires_at=expires_at,
    ))
    await db.flush()
    await send_email_verification(email, raw_token)


async def resend_verification_email(user: User, db: AsyncSession) -> None:
    """为已登录用户重新发送邮箱验证邮件。"""
    if user.email_verified_at:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Email already verified")

    provider = await _find_provider_by_user("email", user.id, db)
    if not provider:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "No email login found for this account")

    await _send_email_verification(user.id, provider.provider_user_id, db)


async def _find_provider_by_user(
    provider: str, user_id, db: AsyncSession
) -> "AuthProvider | None":
    result = await db.execute(
        select(AuthProvider).where(
            AuthProvider.user_id == user_id,
            AuthProvider.provider == provider,
        )
    )
    return result.scalar_one_or_none()


async def verify_email(token: str, db: AsyncSession) -> None:
    token_hash = hash_token(token)
    now = datetime.now(timezone.utc)

    result = await db.execute(
        select(EmailVerificationToken).where(
            EmailVerificationToken.token_hash == token_hash,
            EmailVerificationToken.expires_at > now,
            EmailVerificationToken.used_at.is_(None),
        )
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid or expired verification token")

    record.used_at = now

    result = await db.execute(select(User).where(User.id == record.user_id))
    user = result.scalar_one_or_none()
    if user:
        user.email_verified_at = now
