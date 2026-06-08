from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select

from app.core.dependencies import CurrentUser, DB
from app.models.subscription import Subscription
from app.schemas.subscription import (
    SubscriptionResponse,
    SubscriptionStatusResponse,
    VerifyTransactionRequest,
)
from app.services.apple_iap import IAPError, decode_sk2_transaction

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


@router.get("/status", response_model=SubscriptionStatusResponse)
async def subscription_status(current_user: CurrentUser, db: DB):
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(Subscription).where(
            Subscription.user_id == current_user.id,
            Subscription.is_active == True,  # noqa: E712
            Subscription.expires_at > now,
        )
    )
    sub = result.scalar_one_or_none()
    return SubscriptionStatusResponse(
        is_subscribed=sub is not None,
        subscription=sub,
        expires_at=sub.expires_at if sub else None,
    )


@router.post("/verify", response_model=SubscriptionStatusResponse, status_code=status.HTTP_200_OK)
async def verify_apple_transaction(body: VerifyTransactionRequest, current_user: CurrentUser, db: DB):
    """
    Verify a StoreKit 2 signed transaction from the iOS app.
    Idempotent: re-verifying the same transaction_id refreshes the expiry.
    """
    try:
        info = decode_sk2_transaction(body.jws_transaction)
    except IAPError as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(exc))

    product_id: str = info.get("productId", "")
    transaction_id: str = info.get("transactionId", "")
    original_transaction_id: str = info.get("originalTransactionId", transaction_id)

    expires_ms = info.get("expiresDate")
    if not expires_ms:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Transaction has no expiry (not a subscription?)")
    expires_at = datetime.fromtimestamp(expires_ms / 1000, tz=timezone.utc)

    if expires_at <= datetime.now(timezone.utc):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Transaction already expired")

    # Idempotency: same transaction_id → just refresh expiry
    result = await db.execute(
        select(Subscription).where(Subscription.transaction_id == transaction_id)
    )
    existing = result.scalar_one_or_none()
    if existing:
        existing.is_active = True
        existing.expires_at = expires_at
        await db.flush()
        return SubscriptionStatusResponse(is_subscribed=True, subscription=existing, expires_at=expires_at)

    # Deactivate previous active subscriptions for this user
    old = await db.execute(
        select(Subscription).where(
            Subscription.user_id == current_user.id,
            Subscription.is_active == True,  # noqa: E712
        )
    )
    for old_sub in old.scalars():
        old_sub.is_active = False

    sub = Subscription(
        user_id=current_user.id,
        product_id=product_id,
        transaction_id=transaction_id,
        original_transaction_id=original_transaction_id,
        expires_at=expires_at,
        is_active=True,
    )
    db.add(sub)
    await db.flush()
    return SubscriptionStatusResponse(is_subscribed=True, subscription=sub, expires_at=expires_at)
