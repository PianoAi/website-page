import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class VerifyTransactionRequest(BaseModel):
    jws_transaction: str  # StoreKit 2 signed transaction (JWS string)


class SubscriptionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    product_id: str
    transaction_id: str
    expires_at: datetime
    is_active: bool


class SubscriptionStatusResponse(BaseModel):
    is_subscribed: bool
    subscription: SubscriptionResponse | None = None
    expires_at: datetime | None = None
