import base64
import hashlib
import os

from cryptography.fernet import Fernet, InvalidToken

from .security import SECRET_KEY


def _fernet() -> Fernet:
    configured_key = os.getenv("TOKEN_ENCRYPTION_KEY", "").strip()
    if configured_key:
        return Fernet(configured_key.encode())

    # Local-development fallback. Production must provide a dedicated key.
    derived_key = base64.urlsafe_b64encode(
        hashlib.sha256(f"social9-tokens:{SECRET_KEY}".encode()).digest()
    )
    return Fernet(derived_key)


def encrypt_token(value: str) -> str:
    return _fernet().encrypt(value.encode()).decode()


def decrypt_token(value: str) -> str:
    try:
        return _fernet().decrypt(value.encode()).decode()
    except InvalidToken as error:
        raise ValueError("Unable to decrypt the stored token") from error
