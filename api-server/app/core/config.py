from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Database
    database_url: str

    # JWT
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 30

    # Apple (Sign In + IAP)
    apple_app_bundle_id: str = ""
    apple_shared_secret: str = ""
    apple_verify_url: str = "https://buy.itunes.apple.com/verifyReceipt"
    apple_sandbox_verify_url: str = "https://sandbox.itunes.apple.com/verifyReceipt"

    # Google Sign In
    google_client_id: str = ""

    # S3 / Cloudflare R2
    s3_endpoint_url: str = ""
    s3_access_key_id: str = ""
    s3_secret_access_key: str = ""
    s3_bucket_name: str = "piano-learn"
    s3_region: str = "auto"

    # Twilio (phone OTP)
    twilio_account_sid: str = ""
    twilio_auth_token: str = ""
    twilio_phone_number: str = ""

    # Email (SMTP)
    email_from: str = "noreply@pianoai.app"
    email_from_name: str = "PianoAi"
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_use_tls: bool = True
    # Deep-link base used in email links (e.g. https://pianoai.app or pianoai://)
    app_base_url: str = "pianoai://app"

    # Token expiry
    password_reset_expire_minutes: int = 60      # 1 hour
    email_verify_expire_hours: int = 24           # 24 hours

    # Admin
    admin_api_key: str = ""

    # App
    environment: str = "development"
    debug: bool = False

    @property
    def is_production(self) -> bool:
        return self.environment == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
