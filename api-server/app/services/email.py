import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.core.config import settings

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Templates
# ---------------------------------------------------------------------------

def _password_reset_body(reset_url: str) -> str:
    return f"""\
您好！

我们收到了重置您 PianoAi 账号密码的请求。
请点击以下链接（{settings.password_reset_expire_minutes} 分钟内有效）：

{reset_url}

如果您没有请求重置密码，请忽略此邮件，您的账号仍然安全。

PianoAi 团队
"""


def _email_verify_body(verify_url: str) -> str:
    return f"""\
欢迎加入 PianoAi！

请点击以下链接验证您的邮箱（{settings.email_verify_expire_hours} 小时内有效）：

{verify_url}

验证后即可解锁完整学习功能。

PianoAi 团队
"""


# ---------------------------------------------------------------------------
# Sender
# ---------------------------------------------------------------------------

def _build_message(to: str, subject: str, body: str) -> MIMEMultipart:
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = f"{settings.email_from_name} <{settings.email_from}>"
    msg["To"] = to
    msg.attach(MIMEText(body, "plain", "utf-8"))
    return msg


def _send_smtp(to: str, subject: str, body: str) -> None:
    msg = _build_message(to, subject, body)
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as server:
        if settings.smtp_use_tls:
            server.starttls()
        if settings.smtp_user:
            server.login(settings.smtp_user, settings.smtp_password)
        server.sendmail(settings.email_from, [to], msg.as_string())


async def send_password_reset(to: str, token: str) -> None:
    reset_url = f"{settings.app_base_url}/reset-password?token={token}"
    subject = "PianoAi 密码重置"
    body = _password_reset_body(reset_url)

    if settings.is_production and settings.smtp_host:
        _send_smtp(to, subject, body)
    else:
        # 开发环境：打印到日志，方便调试
        logger.warning(
            "[EMAIL DEV] To=%s | Subject=%s\n%s",
            to, subject, body,
        )


async def send_new_login_notification(
    to: str,
    device_name: str | None,
    platform: str | None,
    ip: str | None,
    location: str | None,
) -> None:
    device_info = f"{device_name or '未知设备'} · {platform or '未知平台'}"
    location_info = f"{location} ({ip})" if location and ip else ip or location or "未知位置"
    from datetime import datetime, timezone
    time_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    subject = "PianoAi 账号新登录通知"
    body = f"""\
您好！

您的 PianoAi 账号刚刚在以下设备和位置完成了登录：

设备：{device_info}
位置：{location_info}
时间：{time_str}

如果这是您本人的操作，请忽略此邮件。
如果不是您的操作，请立即前往 App → 我的 → 安全 → 退出所有其他设备，并修改密码。

PianoAi 团队
"""
    if settings.is_production and settings.smtp_host:
        _send_smtp(to, subject, body)
    else:
        logger.warning("[EMAIL DEV] To=%s | Subject=%s\n%s", to, subject, body)


async def send_email_verification(to: str, token: str) -> None:
    verify_url = f"{settings.app_base_url}/verify-email?token={token}"
    subject = "验证您的 PianoAi 邮箱"
    body = _email_verify_body(verify_url)

    if settings.is_production and settings.smtp_host:
        _send_smtp(to, subject, body)
    else:
        logger.warning(
            "[EMAIL DEV] To=%s | Subject=%s\n%s",
            to, subject, body,
        )
