import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from sqlalchemy import delete as sql_delete

from app.core.config import settings
from app.core.database import engine
from app.core.limiter import limiter
from app.routers import admin, auth, progress, songs, subscriptions

logger = logging.getLogger(__name__)


async def _cleanup_expired_tokens() -> None:
    """每 24 小时清理一次过期/已用 token，防止数据库无限膨胀。"""
    from sqlalchemy.ext.asyncio import AsyncSession
    from app.models.user import EmailVerificationToken, PasswordResetToken, PhoneOtp, RefreshToken

    while True:
        await asyncio.sleep(86_400)  # 24 hours
        try:
            async with AsyncSession(engine) as db:
                now = datetime.now(timezone.utc)
                await db.execute(sql_delete(RefreshToken).where(RefreshToken.expires_at < now))
                await db.execute(sql_delete(PhoneOtp).where(
                    (PhoneOtp.expires_at < now) | (PhoneOtp.is_used == True)  # noqa: E712
                ))
                await db.execute(sql_delete(PasswordResetToken).where(
                    (PasswordResetToken.expires_at < now) | PasswordResetToken.used_at.is_not(None)
                ))
                await db.execute(sql_delete(EmailVerificationToken).where(
                    (EmailVerificationToken.expires_at < now) |
                    EmailVerificationToken.used_at.is_not(None)
                ))
                await db.commit()
                logger.info("Token cleanup completed")
        except Exception:
            logger.exception("Token cleanup failed")


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(_cleanup_expired_tokens())
    yield
    task.cancel()
    await engine.dispose()


app = FastAPI(
    title="PianoLearn API",
    version="1.0.0",
    description="钢琴教学 App 后端 API",
    lifespan=lifespan,
    docs_url="/docs" if not settings.is_production else None,
    redoc_url="/redoc" if not settings.is_production else None,
)

# Rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if not settings.is_production else ["https://pianolearn.com"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    import logging
    logging.getLogger(__name__).exception("Unhandled error on %s %s", request.method, request.url)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "Internal server error"},
    )


app.include_router(auth.router)
app.include_router(songs.router)
app.include_router(progress.router)
app.include_router(subscriptions.router)
app.include_router(admin.router)


@app.get("/health", tags=["meta"])
async def health():
    return {"status": "ok", "env": settings.environment}
