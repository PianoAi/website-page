from fastapi import APIRouter, Header, Request, status

from app.core.dependencies import CurrentUser, DB
from app.core.limiter import limiter
from app.schemas.auth import (
    AppleAuthRequest,
    EmailVerifyRequest,
    GoogleAuthRequest,
    LoginRequest,
    PasswordResetConfirm,
    PasswordResetRequest,
    PhoneOtpRequest,
    PhoneVerifyRequest,
    RefreshRequest,
    RegisterRequest,
    SessionResponse,
    TokenResponse,
)
from app.schemas.user import UpdateProfileRequest, UserResponse
from app.services import auth as auth_svc

router = APIRouter(prefix="/auth", tags=["auth"])


# OTP 按手机号限速（防止单号刷短信）
def _phone_key(request: Request) -> str:
    try:
        import json
        body = json.loads(request._body)
        return body.get("phone_number", request.client.host)
    except Exception:
        return request.client.host


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("5/minute")          # 每 IP 每分钟最多 5 次注册
async def register(request: Request, body: RegisterRequest, db: DB):
    return await auth_svc.register_email(body.email, body.password, body.display_name, db)


@router.post("/login", response_model=TokenResponse)
@limiter.limit("10/minute")
async def login(
    request: Request,
    body: LoginRequest,
    db: DB,
    x_device_name: str | None = Header(default=None),
    x_platform:    str | None = Header(default=None),
):
    ip = request.client.host if request.client else None
    return await auth_svc.login_email(
        body.email, body.password, db,
        device_name=x_device_name, platform=x_platform, ip=ip,
    )


@router.post("/apple", response_model=TokenResponse)
@limiter.limit("10/minute")
async def apple_sign_in(request: Request, body: AppleAuthRequest, db: DB):
    return await auth_svc.auth_apple(body.identity_token, body.display_name, db)


@router.post("/google", response_model=TokenResponse)
@limiter.limit("10/minute")
async def google_sign_in(request: Request, body: GoogleAuthRequest, db: DB):
    return await auth_svc.auth_google(body.id_token, body.display_name, db)


@router.post("/phone/otp", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("3/10minutes", key_func=_phone_key)   # 同一手机号每 10 分钟最多 3 次
async def request_otp(request: Request, body: PhoneOtpRequest, db: DB):
    await auth_svc.send_phone_otp(body.phone_number, db)


@router.post("/phone/verify", response_model=TokenResponse)
@limiter.limit("10/minute")
async def verify_otp(request: Request, body: PhoneVerifyRequest, db: DB):
    return await auth_svc.verify_phone_otp(body.phone_number, body.otp, db)


@router.post("/refresh", response_model=TokenResponse)
@limiter.limit("30/minute")         # refresh 合法高频，放宽
async def refresh(request: Request, body: RefreshRequest, db: DB):
    return await auth_svc.refresh_tokens(body.refresh_token, db)


@router.delete("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: RefreshRequest, db: DB):
    await auth_svc.logout(body.refresh_token, db)


@router.get("/me", response_model=UserResponse)
async def me(current_user: CurrentUser):
    return current_user


@router.patch("/me", response_model=UserResponse)
async def update_me(body: UpdateProfileRequest, current_user: CurrentUser, db: DB):
    if body.display_name is not None:
        current_user.display_name = body.display_name
    if body.avatar_url is not None:
        current_user.avatar_url = body.avatar_url
    db.add(current_user)
    return current_user


# ---------------------------------------------------------------------------
# Password reset
# ---------------------------------------------------------------------------

@router.post("/password-reset/request", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("3/10minutes")       # 防止枚举邮箱
async def password_reset_request(request: Request, body: PasswordResetRequest, db: DB):
    """请求密码重置邮件。无论邮箱是否存在都返回 204（防止邮箱枚举）。"""
    await auth_svc.request_password_reset(body.email, db)


@router.post("/password-reset/confirm", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("5/minute")
async def password_reset_confirm(request: Request, body: PasswordResetConfirm, db: DB):
    """用邮件中的 token 设置新密码。"""
    await auth_svc.confirm_password_reset(body.token, body.new_password, db)


# ---------------------------------------------------------------------------
# Email verification
# ---------------------------------------------------------------------------

@router.post("/verify-email", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("10/minute")
async def verify_email(request: Request, body: EmailVerifyRequest, db: DB):
    """验证邮箱 token（注册后邮件中的链接）。"""
    await auth_svc.verify_email(body.token, db)


@router.post("/resend-verification", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("3/hour")          # 防止滥发邮件
async def resend_verification(request: Request, current_user: CurrentUser, db: DB):
    """为已登录用户重新发送邮箱验证邮件。"""
    await auth_svc.resend_verification_email(current_user, db)


# ---------------------------------------------------------------------------
# Session management
# ---------------------------------------------------------------------------

@router.get("/sessions", response_model=list[SessionResponse])
async def get_sessions(
    current_user: CurrentUser,
    db: DB,
    x_session_id: str | None = Header(default=None),
):
    """列出当前用户的所有活跃会话。"""
    return await auth_svc.list_sessions(str(current_user.id), x_session_id, db)


@router.delete("/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_session(session_id: str, current_user: CurrentUser, db: DB):
    """撤销指定会话（用于踢出特定设备）。"""
    await auth_svc.revoke_session(session_id, str(current_user.id), db)


@router.delete("/sessions", status_code=status.HTTP_200_OK)
async def revoke_other_sessions(
    current_user: CurrentUser,
    db: DB,
    x_session_id: str | None = Header(default=None),
):
    """撤销当前设备之外的所有会话，返回撤销数量。"""
    count = await auth_svc.revoke_other_sessions(str(current_user.id), x_session_id, db)
    return {"revoked": count}
