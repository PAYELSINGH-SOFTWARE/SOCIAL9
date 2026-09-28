import hashlib
import hmac
import os
from datetime import datetime, timedelta, timezone

from dotenv import load_dotenv
from jose import jwt


load_dotenv()

ALGORITHM = "HS256"
SECRET_KEY = os.getenv("SOCIAL9_SECRET_KEY", "development-only-change-me")
TOKEN_TTL_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "10080"))
ACTION_TOKEN_TTL_MINUTES = int(os.getenv("ACTION_TOKEN_EXPIRE_MINUTES", "30"))


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    password_hash = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, 210_000
    )
    return f"{salt.hex()}:{password_hash.hex()}"


def verify_password(password: str, stored_value: str) -> bool:
    try:
        salt_hex, stored_hash_hex = stored_value.split(":", 1)
        salt = bytes.fromhex(salt_hex)
        stored_hash = bytes.fromhex(stored_hash_hex)
    except (ValueError, TypeError):
        return False

    candidate_hash = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, 210_000
    )
    return hmac.compare_digest(candidate_hash, stored_hash)


def create_access_token(subject: str) -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=TOKEN_TTL_MINUTES)
    return jwt.encode(
        {"sub": subject, "purpose": "access", "exp": expires_at},
        SECRET_KEY,
        algorithm=ALGORITHM,
    )


def create_action_token(
    subject: str, purpose: str, extra_claims: dict[str, str] | None = None
) -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=ACTION_TOKEN_TTL_MINUTES
    )
    payload = {"sub": subject, "purpose": purpose, "exp": expires_at}
    if extra_claims:
        payload.update(extra_claims)
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_action_token(token: str, purpose: str) -> dict[str, str]:
    payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    if payload.get("purpose") != purpose or not payload.get("sub"):
        raise ValueError("Invalid token purpose")
    return payload


def password_fingerprint(hashed_password: str) -> str:
    return hashlib.sha256(hashed_password.encode("utf-8")).hexdigest()
