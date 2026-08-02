import base64
import hashlib
import html
import json
import os
import secrets
from datetime import datetime, timedelta, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from cryptography.fernet import Fernet
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import HTMLResponse
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from ..models import SocialAccount, SocialLoginAttempt, User
from .auth import ALGORITHM, SECRET_KEY, create_access_token, get_current_user, get_db, hash_password

router = APIRouter()
PROVIDERS = {
    "instagram": {"client_id": "INSTAGRAM_CLIENT_ID", "client_secret": "INSTAGRAM_CLIENT_SECRET", "redirect_uri": "INSTAGRAM_REDIRECT_URI", "authorization_url": "https://www.instagram.com/oauth/authorize", "token_url": "https://api.instagram.com/oauth/access_token", "profile_url": "https://graph.instagram.com/me?fields=user_id,username", "scope": "instagram_business_basic,instagram_business_content_publish"},
    "linkedin": {"client_id": "LINKEDIN_CLIENT_ID", "client_secret": "LINKEDIN_CLIENT_SECRET", "redirect_uri": "LINKEDIN_REDIRECT_URI", "authorization_url": "https://www.linkedin.com/oauth/v2/authorization", "token_url": "https://www.linkedin.com/oauth/v2/accessToken", "profile_url": "https://api.linkedin.com/v2/userinfo", "scope": "openid profile email w_member_social"},
}


def token_cipher():
    secret = os.getenv("SOCIAL9_TOKEN_ENCRYPTION_KEY", SECRET_KEY)
    return Fernet(base64.urlsafe_b64encode(hashlib.sha256(secret.encode()).digest()))


def encrypt_token(value: str | None):
    return token_cipher().encrypt(value.encode()).decode() if value else None


def decrypt_token(value: str | None):
    return token_cipher().decrypt(value.encode()).decode() if value else None


def provider_configured(provider: str):
    config = PROVIDERS[provider]
    return all(os.getenv(config[key]) for key in ("client_id", "client_secret", "redirect_uri"))


def provider_status(provider: str, account: SocialAccount | None = None):
    expired = bool(account and account.token_expires_at and account.token_expires_at.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc))
    return {"provider": provider, "configured": provider_configured(provider), "connected": account is not None and not expired, "display_name": account.display_name if account else None, "status": "expired" if expired else account.status if account else "not_connected", "token_expires_at": account.token_expires_at if account else None}


def post_form(url: str, values: dict):
    request = Request(url, data=urlencode(values).encode(), headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urlopen(request, timeout=15) as response:
            return json.loads(response.read())
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=502, detail="Provider token exchange failed") from exc


def get_json(url: str, access_token: str):
    request = Request(url, headers={"Authorization": f"Bearer {access_token}"})
    try:
        with urlopen(request, timeout=15) as response:
            return json.loads(response.read())
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=502, detail="Provider profile lookup failed") from exc


def exchange_provider_code(provider: str, code: str):
    config = PROVIDERS[provider]
    return post_form(config["token_url"], {"grant_type": "authorization_code", "code": code, "client_id": os.environ[config["client_id"]], "client_secret": os.environ[config["client_secret"]], "redirect_uri": os.environ[config["redirect_uri"]]})


def fetch_provider_profile(provider: str, access_token: str):
    data = get_json(PROVIDERS[provider]["profile_url"], access_token)
    if provider == "linkedin":
        return str(data.get("sub", "")), data.get("name") or data.get("email") or "LinkedIn account"
    return str(data.get("user_id") or data.get("id") or ""), data.get("username") or "Instagram account"


def build_provider_url(provider: str, state: str):
    config = PROVIDERS[provider]
    scope = config["scope"]
    if (
        provider == "linkedin"
        and os.getenv("LINKEDIN_ENABLE_ANALYTICS", "false").lower() == "true"
    ):
        scope = f"{scope} r_member_postAnalytics"
    query = urlencode({"response_type": "code", "client_id": os.environ[config["client_id"]], "redirect_uri": os.environ[config["redirect_uri"]], "state": state, "scope": scope})
    return f'{config["authorization_url"]}?{query}'


@router.get("")
def list_accounts(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    accounts = {item.provider: item for item in db.query(SocialAccount).filter(SocialAccount.owner_id == user.id).all()}
    return [provider_status(provider, accounts.get(provider)) for provider in PROVIDERS]


@router.post("/{provider}/authorization-url")
def authorization_url(provider: str, user: User = Depends(get_current_user)):
    if provider not in PROVIDERS:
        raise HTTPException(status_code=404, detail="Unsupported provider")
    if not provider_configured(provider):
        raise HTTPException(status_code=503, detail=f"{provider.title()} developer credentials are not configured")
    state = jwt.encode({"sub": str(user.id), "provider": provider, "exp": datetime.now(timezone.utc) + timedelta(minutes=10)}, SECRET_KEY, algorithm=ALGORITHM)
    return {"authorization_url": build_provider_url(provider, state)}


@router.post("/{provider}/login-url")
def social_login_url(provider: str, db: Session = Depends(get_db)):
    if provider not in PROVIDERS:
        raise HTTPException(status_code=404, detail="Unsupported provider")
    if not provider_configured(provider):
        raise HTTPException(status_code=503, detail=f"{provider.title()} login is not configured")
    attempt_id = secrets.token_urlsafe(32)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
    db.add(SocialLoginAttempt(id=attempt_id, provider=provider, status="pending", expires_at=expires_at))
    db.commit()
    state = jwt.encode({"attempt": attempt_id, "provider": provider, "mode": "login", "exp": expires_at}, SECRET_KEY, algorithm=ALGORITHM)
    return {"attempt_id": attempt_id, "authorization_url": build_provider_url(provider, state)}


@router.get("/login-status/{attempt_id}")
def social_login_status(attempt_id: str, db: Session = Depends(get_db)):
    attempt = db.query(SocialLoginAttempt).filter(SocialLoginAttempt.id == attempt_id).first()
    if attempt is None:
        raise HTTPException(status_code=404, detail="Login attempt not found")
    if attempt.expires_at.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        return {"status": "expired"}
    if attempt.status == "completed" and attempt.app_token_encrypted:
        token = decrypt_token(attempt.app_token_encrypted)
        db.delete(attempt)
        db.commit()
        return {"status": "completed", "access_token": token}
    return {"status": attempt.status, "error": attempt.error_message}


@router.get("/{provider}/callback", response_class=HTMLResponse)
def oauth_callback(provider: str, code: str | None = Query(default=None), state: str | None = Query(default=None), error: str | None = Query(default=None), error_description: str | None = Query(default=None), db: Session = Depends(get_db)):
    if provider not in PROVIDERS:
        raise HTTPException(status_code=404, detail="Unsupported provider")
    if error:
        return HTMLResponse(f"<h1>Connection cancelled</h1><p>{html.escape(error_description or error)}</p>", status_code=400)
    if not code or not state:
        raise HTTPException(status_code=400, detail="Missing OAuth code or state")
    try:
        payload = jwt.decode(state, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("provider") != provider:
            raise JWTError("Provider mismatch")
    except (JWTError, KeyError, ValueError) as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired OAuth state") from exc

    token_data = exchange_provider_code(provider, code)
    access_token = token_data.get("access_token")
    if not access_token:
        raise HTTPException(status_code=502, detail="Provider did not return an access token")
    external_id, display_name = fetch_provider_profile(provider, access_token)
    if not external_id:
        raise HTTPException(status_code=502, detail="Provider did not return an account identifier")
    expires_in = token_data.get("expires_in")
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=int(expires_in)) if expires_in else None

    if payload.get("mode") == "login":
        attempt = db.query(SocialLoginAttempt).filter(SocialLoginAttempt.id == payload.get("attempt"), SocialLoginAttempt.provider == provider).first()
        if attempt is None:
            raise HTTPException(status_code=401, detail="Login attempt no longer exists")
        account = db.query(SocialAccount).filter(SocialAccount.provider == provider, SocialAccount.external_account_id == external_id).first()
        if account is None:
            user = User(name=display_name, email=f"{provider}_{external_id}@social9.local", hashed_password=hash_password(secrets.token_urlsafe(32)))
            db.add(user)
            db.flush()
            account = SocialAccount(owner_id=user.id, provider=provider, external_account_id=external_id, display_name=display_name, access_token_encrypted=encrypt_token(access_token))
            db.add(account)
        else:
            user = account.owner
            account.display_name = display_name
            account.access_token_encrypted = encrypt_token(access_token)
        account.refresh_token_encrypted = encrypt_token(token_data.get("refresh_token"))
        account.token_expires_at = expires_at
        account.status = "connected"
        attempt.app_token_encrypted = encrypt_token(create_access_token({"sub": user.email}))
        attempt.status = "completed"
        db.commit()
        return HTMLResponse(f"<h1>{provider.title()} login complete</h1><p>You can close this tab and return to vCueSocial9.</p>")

    try:
        user_id = int(payload["sub"])
    except (KeyError, ValueError) as exc:
        raise HTTPException(status_code=401, detail="Invalid connection state") from exc
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=401, detail="User no longer exists")
    account = db.query(SocialAccount).filter(SocialAccount.owner_id == user.id, SocialAccount.provider == provider).first()
    if account is None:
        account = SocialAccount(owner_id=user.id, provider=provider, external_account_id=external_id, display_name=display_name, access_token_encrypted=encrypt_token(access_token))
        db.add(account)
    else:
        account.external_account_id = external_id
        account.display_name = display_name
        account.access_token_encrypted = encrypt_token(access_token)
    account.refresh_token_encrypted = encrypt_token(token_data.get("refresh_token"))
    account.token_expires_at = expires_at
    account.status = "connected"
    db.commit()
    return HTMLResponse(f"<h1>{provider.title()} connected</h1><p>You can return to vCueSocial9.</p>")


@router.delete("/{provider}", status_code=204)
def disconnect(provider: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    account = db.query(SocialAccount).filter(SocialAccount.owner_id == user.id, SocialAccount.provider == provider).first()
    if account is None:
        raise HTTPException(status_code=404, detail="Connected account not found")
    db.delete(account)
    db.commit()

