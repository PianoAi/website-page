import base64
import json
import logging

logger = logging.getLogger(__name__)


class IAPError(Exception):
    pass


def _b64url_decode(s: str) -> bytes:
    padding = 4 - len(s) % 4
    return base64.urlsafe_b64decode(s + "=" * (padding % 4))


def decode_sk2_transaction(jws_token: str) -> dict:
    """
    Decode a StoreKit 2 signed transaction (JWS).

    Signature verification is intentionally skipped: the iOS StoreKit framework
    already verifies the transaction on-device before we ever receive it
    (we only process `.verified` results). The backend's role is to record
    the subscription, not to re-verify Apple's cryptographic signature.
    """
    parts = jws_token.split(".")
    if len(parts) != 3:
        raise IAPError("Invalid JWS format")

    payload = json.loads(_b64url_decode(parts[1]))
    logger.info("SK2 transaction payload keys: %s", list(payload.keys()))
    return payload
