#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.request


ENDPOINT = "https://dnspod.tencentcloudapi.com"
SERVICE = "dnspod"
VERSION = "2021-03-23"


def sign(secret_id: str, secret_key: str, action: str, payload: str, timestamp: int) -> str:
    date = dt.datetime.fromtimestamp(timestamp, dt.UTC).strftime("%Y-%m-%d")
    canonical_headers = (
        f"content-type:application/json\n"
        f"host:{SERVICE}.tencentcloudapi.com\n"
        f"x-tc-action:{action.lower()}\n"
    )
    signed_headers = "content-type;host;x-tc-action"
    canonical_request = "\n".join(
        [
            "POST",
            "/",
            "",
            canonical_headers,
            signed_headers,
            hashlib.sha256(payload.encode("utf-8")).hexdigest(),
        ]
    )
    credential_scope = f"{date}/{SERVICE}/tc3_request"
    string_to_sign = "\n".join(
        [
            "TC3-HMAC-SHA256",
            str(timestamp),
            credential_scope,
            hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
        ]
    )

    def digest(key: bytes, msg: str) -> bytes:
        return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()

    secret_date = digest(("TC3" + secret_key).encode("utf-8"), date)
    secret_service = digest(secret_date, SERVICE)
    secret_signing = digest(secret_service, "tc3_request")
    signature = hmac.new(
        secret_signing, string_to_sign.encode("utf-8"), hashlib.sha256
    ).hexdigest()
    return (
        f"TC3-HMAC-SHA256 Credential={secret_id}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )


def request(secret_id: str, secret_key: str, action: str, body: dict[str, object]) -> dict:
    payload = json.dumps(body, separators=(",", ":"), ensure_ascii=False)
    timestamp = int(time.time())
    req = urllib.request.Request(
        ENDPOINT,
        data=payload.encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": sign(secret_id, secret_key, action, payload, timestamp),
            "X-TC-Version": VERSION,
            "X-TC-Timestamp": str(timestamp),
            "X-TC-Action": action,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        data = json.loads(exc.read().decode("utf-8"))
    response = data.get("Response", data)
    if "Error" in response:
        message = response["Error"].get("Message", response["Error"])
        raise RuntimeError(f"{action} failed: {message}")
    return response


def find_a_record(secret_id: str, secret_key: str, domain: str, subdomain: str) -> dict | None:
    try:
        response = request(
            secret_id,
            secret_key,
            "DescribeRecordList",
            {"Domain": domain, "Subdomain": subdomain, "RecordType": "A", "Limit": 3000},
        )
    except RuntimeError as exc:
        if "记录列表为空" in str(exc):
            return None
        raise
    records = response.get("RecordList", [])
    for record in records:
        if record.get("Name") == subdomain and record.get("Type") == "A":
            return record
    return None


def upsert_a_record(
    secret_id: str, secret_key: str, domain: str, subdomain: str, value: str
) -> None:
    record = find_a_record(secret_id, secret_key, domain, subdomain)
    if record:
        old_value = record.get("Value")
        record_id = record["RecordId"]
        line = record.get("Line") or "默认"
        ttl = int(record.get("TTL") or 600)
        if old_value == value:
            print(f"unchanged: {subdomain}.{domain} A {value} record_id={record_id}")
            return
        request(
            secret_id,
            secret_key,
            "ModifyRecord",
            {
                "Domain": domain,
                "SubDomain": subdomain,
                "RecordType": "A",
                "RecordLine": line,
                "Value": value,
                "RecordId": record_id,
                "TTL": ttl,
            },
        )
        print(
            f"updated: {subdomain}.{domain} A {old_value} -> {value} "
            f"record_id={record_id}"
        )
        return
    response = request(
        secret_id,
        secret_key,
        "CreateRecord",
        {
            "Domain": domain,
            "SubDomain": subdomain,
            "RecordType": "A",
            "RecordLine": "默认",
            "Value": value,
            "TTL": 600,
        },
    )
    print(f"created: {subdomain}.{domain} A {value} record_id={response.get('RecordId')}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--domain", required=True)
    parser.add_argument("--subdomain", required=True)
    parser.add_argument("--value", required=True)
    args = parser.parse_args()

    secret_id = os.environ.get("Tencent_SecretId")
    secret_key = os.environ.get("Tencent_SecretKey")
    if not secret_id or not secret_key:
        print("Tencent_SecretId/Tencent_SecretKey are required", file=sys.stderr)
        return 2
    upsert_a_record(secret_id, secret_key, args.domain, args.subdomain, args.value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
