import boto3
from botocore.config import Config

from app.core.config import settings


def _s3_client():
    kwargs: dict = {
        "region_name": settings.s3_region,
        "aws_access_key_id": settings.s3_access_key_id,
        "aws_secret_access_key": settings.s3_secret_access_key,
        "config": Config(signature_version="s3v4"),
    }
    if settings.s3_endpoint_url:
        kwargs["endpoint_url"] = settings.s3_endpoint_url
    return boto3.client("s3", **kwargs)


def get_presigned_download_url(s3_key: str, expires_in: int = 3600) -> str:
    return _s3_client().generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.s3_bucket_name, "Key": s3_key},
        ExpiresIn=expires_in,
    )


def get_presigned_upload_url(s3_key: str, content_type: str, expires_in: int = 900) -> str:
    return _s3_client().generate_presigned_url(
        "put_object",
        Params={
            "Bucket": settings.s3_bucket_name,
            "Key": s3_key,
            "ContentType": content_type,
        },
        ExpiresIn=expires_in,
    )


def upload_bytes(s3_key: str, data: bytes, content_type: str = "audio/midi") -> None:
    _s3_client().put_object(
        Bucket=settings.s3_bucket_name,
        Key=s3_key,
        Body=data,
        ContentType=content_type,
    )


def delete_object(s3_key: str) -> None:
    _s3_client().delete_object(Bucket=settings.s3_bucket_name, Key=s3_key)


def object_exists(s3_key: str) -> bool:
    from botocore.exceptions import ClientError
    try:
        _s3_client().head_object(Bucket=settings.s3_bucket_name, Key=s3_key)
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] in ("404", "NoSuchKey"):
            return False
        raise
