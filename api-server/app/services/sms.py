import logging
from abc import ABC, abstractmethod
from base64 import b64encode

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


class SmsService(ABC):
    @abstractmethod
    async def send(self, to: str, message: str) -> None: ...


class ConsoleSmsService(SmsService):
    """Development fallback — prints OTP to server logs instead of sending SMS."""

    async def send(self, to: str, message: str) -> None:
        logger.warning("[SMS DEV] To=%s | %s", to, message)


class TwilioSmsService(SmsService):
    async def send(self, to: str, message: str) -> None:
        creds = b64encode(
            f"{settings.twilio_account_sid}:{settings.twilio_auth_token}".encode()
        ).decode()
        url = (
            f"https://api.twilio.com/2010-04-01/Accounts/"
            f"{settings.twilio_account_sid}/Messages.json"
        )
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                url,
                data={
                    "From": settings.twilio_phone_number,
                    "To": to,
                    "Body": message,
                },
                headers={"Authorization": f"Basic {creds}"},
                timeout=10.0,
            )
            resp.raise_for_status()


def get_sms_service() -> SmsService:
    if settings.is_production and settings.twilio_account_sid:
        return TwilioSmsService()
    return ConsoleSmsService()
