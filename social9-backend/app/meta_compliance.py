import base64
import hashlib
import hmac
import json
import os
import secrets
from datetime import datetime, timezone
from urllib.parse import parse_qs, quote

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from .auth import get_db
from .models import SocialAccount


router = APIRouter(prefix="/meta/instagram", tags=["Meta compliance"])


def _decode_base64url(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def _encode_base64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def _meta_app_secret() -> str:
    secret = os.getenv("META_APP_SECRET", "").strip() or os.getenv(
        "INSTAGRAM_CLIENT_SECRET", ""
    ).strip()
    if not secret:
        raise HTTPException(status_code=503, detail="Meta compliance is not configured")
    return secret


def _verify_signed_request(signed_request: str) -> str:
    try:
        encoded_signature, encoded_payload = signed_request.split(".", 1)
        supplied_signature = _decode_base64url(encoded_signature)
        expected_signature = hmac.new(
            _meta_app_secret().encode(),
            encoded_payload.encode(),
            hashlib.sha256,
        ).digest()
        if not hmac.compare_digest(supplied_signature, expected_signature):
            raise ValueError("signature mismatch")
        payload = json.loads(_decode_base64url(encoded_payload))
        if str(payload.get("algorithm", "HMAC-SHA256")).upper() != "HMAC-SHA256":
            raise ValueError("unsupported algorithm")
        provider_user_id = payload.get("user_id") or payload.get("app_scoped_user_id")
        if not provider_user_id:
            raise ValueError("missing user id")
        return str(provider_user_id)
    except (ValueError, TypeError, json.JSONDecodeError):
        raise HTTPException(status_code=400, detail="Invalid Meta signed request") from None


async def _signed_request_from_body(request: Request) -> str:
    body = (await request.body()).decode("utf-8", errors="replace")
    signed_request = parse_qs(body).get("signed_request", [""])[0]
    if not signed_request:
        raise HTTPException(status_code=400, detail="Meta signed request is required")
    return signed_request


def _completion_code(provider_user_id: str) -> str:
    payload = {
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "request": secrets.token_urlsafe(12),
        "subject": hashlib.sha256(provider_user_id.encode()).hexdigest()[:16],
        "status": "completed",
    }
    encoded = _encode_base64url(
        json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    )
    signature = hmac.new(
        os.getenv("SOCIAL9_SECRET_KEY", "development-only-secret").encode(),
        encoded.encode(),
        hashlib.sha256,
    ).digest()
    return f"{encoded}.{_encode_base64url(signature)}"


def _read_completion_code(code: str) -> dict[str, str]:
    try:
        encoded, encoded_signature = code.split(".", 1)
        expected = hmac.new(
            os.getenv("SOCIAL9_SECRET_KEY", "development-only-secret").encode(),
            encoded.encode(),
            hashlib.sha256,
        ).digest()
        if not hmac.compare_digest(_decode_base64url(encoded_signature), expected):
            raise ValueError("signature mismatch")
        payload = json.loads(_decode_base64url(encoded))
        if payload.get("status") != "completed" or not payload.get("completed_at"):
            raise ValueError("invalid status")
        return {
            "status": "completed",
            "completed_at": str(payload["completed_at"]),
            "confirmation_code": code,
        }
    except (ValueError, TypeError, json.JSONDecodeError):
        raise HTTPException(status_code=404, detail="Deletion request not found") from None


def _remove_instagram_connection(database: Session, provider_user_id: str) -> None:
    accounts = (
        database.query(SocialAccount)
        .filter(
            SocialAccount.provider == "instagram",
            SocialAccount.provider_account_id == provider_user_id,
        )
        .all()
    )
    for account in accounts:
        database.delete(account)
    database.commit()


@router.post("/deauthorize")
async def deauthorize_instagram(
    request: Request,
    database: Session = Depends(get_db),
) -> dict[str, bool]:
    provider_user_id = _verify_signed_request(await _signed_request_from_body(request))
    _remove_instagram_connection(database, provider_user_id)
    return {"success": True}


@router.post("/data-deletion")
async def delete_instagram_data(
    request: Request,
    database: Session = Depends(get_db),
) -> dict[str, str]:
    provider_user_id = _verify_signed_request(await _signed_request_from_body(request))
    _remove_instagram_connection(database, provider_user_id)
    code = _completion_code(provider_user_id)
    frontend_url = os.getenv("FRONTEND_URL", "http://localhost:3000").rstrip("/")
    return {
        "url": f"{frontend_url}/data-deletion?code={quote(code, safe='')}",
        "confirmation_code": code,
    }


@router.get("/data-deletion/status")
def data_deletion_status(code: str) -> dict[str, str]:
    return _read_completion_code(code)
