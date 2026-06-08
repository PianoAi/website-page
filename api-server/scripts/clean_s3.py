#!/usr/bin/env python3
"""
清空 S3/Garage 桶中 midi/ 前缀下的所有对象。
运行前确认 .env 中 S3 配置正确。

用法:
    python scripts/clean_s3.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import boto3
from botocore.config import Config
from app.core.config import settings


def main() -> None:
    kwargs: dict = {
        "region_name": settings.s3_region,
        "aws_access_key_id": settings.s3_access_key_id,
        "aws_secret_access_key": settings.s3_secret_access_key,
        "config": Config(signature_version="s3v4"),
    }
    if settings.s3_endpoint_url:
        kwargs["endpoint_url"] = settings.s3_endpoint_url

    s3 = boto3.client("s3", **kwargs)
    bucket = settings.s3_bucket_name
    prefix = "midi/"

    paginator = s3.get_paginator("list_objects_v2")
    total_deleted = 0

    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        objects = page.get("Contents", [])
        if not objects:
            continue

        keys = [{"Key": o["Key"]} for o in objects]
        resp = s3.delete_objects(Bucket=bucket, Delete={"Objects": keys})
        deleted = len(resp.get("Deleted", []))
        errors  = resp.get("Errors", [])
        total_deleted += deleted

        if errors:
            for e in errors:
                print(f"  ✗ {e['Key']}: {e['Message']}")

    print(f"✓ 已删除 {total_deleted} 个对象（前缀 {prefix}）")


if __name__ == "__main__":
    main()
