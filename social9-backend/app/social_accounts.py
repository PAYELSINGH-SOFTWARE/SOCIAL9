import hashlib
import os
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session

from .auth import get_current_user, get_db
from .encryption import encrypt_token
from .models import OAuthState, SocialAccount, User
from .social_schemas import ConnectResponse, ProviderStatusResponse, SocialAccountResponse


router = APIRouter(prefix="/social-accounts", tags=["Social accounts"])
SUPPORTED_PROVIDERS = {"instagram", "linkedin"}
INSTAGRAM_TOKEN_URL = "https://api.instagram.com/oauth/access_token"
INSTAGRAM_GRAPH_URL = "https://graph.instagram.com"
LINKEDIN_TOKEN_URL = "https://www.linkedin.com/oauth/v2/accessToken"
LINKEDIN_USERINFO_URL = "https://api.linkedin.com/v2/userinfo"


class InstagramExchangeError(RuntimeError):
    """A safe, provider-neutral Instagram authorization failure."""


class LinkedInExchangeError(RuntimeError):
    """A safe, provider-neutral LinkedIn authorization failure."""


@dataclass(frozen=True)
class ProviderAccountData:
    provider_account_id: str
    account_name: str
    username: str | None
    access_token: str
    refresh_token: str | None
    expires_at: datetime | None


def _state_hash(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def _frontend_url() -> str:
    return os.getenv("FRONTEND_URL", "http://localhost:3000").rstrip("/")


def _accounts_redirect(**parameters: str) -> str:
    return f"{_frontend_url()}/accounts?{urlencode(parameters)}"


def _mock_mode(provider: str) -> bool:
    provider_setting = os.getenv(f"{provider.upper()}_OAUTH_MOCK_MODE")
    if provider_setting is not None:
        return provider_setting.lower() == "true"
    return os.getenv("OAUTH_MOCK_MODE", "true").lower() == "true"


def _callback_url(provider: str) -> str:
    configured = os.getenv(f"{provider.upper()}_REDIRECT_URI", "").strip()
    if configured:
        return configured

    backend_url = os.getenv("RENDER_EXTERNAL_URL", "http://127.0.0.1:8000")
    return f"{backend_url.rstrip('/')}/social-accounts/{provider}/callback"


def _authorization_url(provider: str, state_value: str) -> str:
    callback = _callback_url(provider)
    if _mock_mode(provider):
        return f"{_frontend_url()}/oauth/mock?{urlencode({'provider': provider, 'state': state_value})}"

    client_id = os.getenv(f"{provider.upper()}_CLIENT_ID", "").strip()
    if not client_id:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"{provider.title()} OAuth credentials are not configured yet",
        )

    if provider == "instagram":
        base_url = "https://www.instagram.com/oauth/authorize"
        scope = os.getenv(
            "INSTAGRAM_SCOPES",
            "instagram_business_basic,instagram_business_content_publish,instagram_business_manage_insights",
        )
        provider_parameters = {
            "enable_fb_login": "false",
            "force_reauth": "true",
        }
    else:
        base_url = "https://www.linkedin.com/oauth/v2/authorization"
        scope = os.getenv("LINKEDIN_SCOPES", "openid profile email w_member_social")
        provider_parameters = {}

    return f"{base_url}?{urlencode({'client_id': client_id, 'redirect_uri': callback, 'response_type': 'code', 'scope': scope, 'state': state_value, **provider_parameters})}"


def _provider_configured(provider: str) -> bool:
    return all(
        os.getenv(f"{provider.upper()}_{suffix}", "").strip()
        for suffix in ("CLIENT_ID", "CLIENT_SECRET")
    )


def _instagram_credentials() -> tuple[str, str]:
    client_id = os.getenv("INSTAGRAM_CLIENT_ID", "").strip()
    client_secret = os.getenv("INSTAGRAM_CLIENT_SECRET", "").strip()
    if not client_id or not client_secret:
        raise InstagramExchangeError("Instagram credentials are not configured")
    return client_id, client_secret


def _response_json(response: httpx.Response) -> dict:
    if not response.is_success:
        raise InstagramExchangeError("Instagram rejected the authorization request")
    try:
        payload = response.json()
    except ValueError as error:
        raise InstagramExchangeError("Instagram returned an invalid response") from error
    if not isinstance(payload, dict):
        raise InstagramExchangeError("Instagram returned an invalid response")
    return payload


def _exchange_instagram_code(code: str) -> ProviderAccountData:
    client_id, client_secret = _instagram_credentials()
    callback = _callback_url("instagram")
    try:
        with httpx.Client(timeout=15.0) as client:
            short_response = client.post(
                INSTAGRAM_TOKEN_URL,
                data={
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "grant_type": "authorization_code",
                    "redirect_uri": callback,
                    "code": code,
                },
                headers={"Accept": "application/json"},
            )
            short_payload = _response_json(short_response)
            short_token = short_payload.get("access_token")
            if not isinstance(short_token, str) or not short_token:
                raise InstagramExchangeError("Instagram did not return an access token")

            long_response = client.get(
                f"{INSTAGRAM_GRAPH_URL}/access_token",
                params={
                    "grant_type": "ig_exchange_token",
                    "client_secret": client_secret,
                    "access_token": short_token,
                },
                headers={"Accept": "application/json"},
            )
            long_payload = _response_json(long_response)
            long_token = long_payload.get("access_token")
            if not isinstance(long_token, str) or not long_token:
                raise InstagramExchangeError("Instagram did not return a long-lived token")

            profile_response = client.get(
                f"{INSTAGRAM_GRAPH_URL}/me",
                params={
                    "fields": "id,user_id,username,name,account_type,profile_picture_url",
                    "access_token": long_token,
                },
                headers={"Accept": "application/json"},
            )
            profile = _response_json(profile_response)
    except httpx.HTTPError as error:
        raise InstagramExchangeError("Instagram could not be reached") from error

    account_id = profile.get("user_id") or short_payload.get("user_id") or profile.get("id")
    if account_id is None:
        raise InstagramExchangeError("Instagram did not return an account identifier")
    username = profile.get("username")
    display_name = profile.get("name") or username or "Instagram account"
    expires_in = long_payload.get("expires_in")
    try:
        lifetime = int(expires_in) if expires_in is not None else 60 * 24 * 60 * 60
    except (TypeError, ValueError):
        lifetime = 60 * 24 * 60 * 60

    return ProviderAccountData(
        provider_account_id=str(account_id),
        account_name=str(display_name),
        username=str(username) if username else None,
        access_token=long_token,
        refresh_token=None,
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=max(0, lifetime)),
    )


def _linkedin_credentials() -> tuple[str, str]:
    client_id = os.getenv("LINKEDIN_CLIENT_ID", "").strip()
    client_secret = os.getenv("LINKEDIN_CLIENT_SECRET", "").strip()
    if not client_id or not client_secret:
        raise LinkedInExchangeError("LinkedIn credentials are not configured")
    return client_id, client_secret


def _linkedin_response_json(response: httpx.Response) -> dict:
    if not response.is_success:
        raise LinkedInExchangeError("LinkedIn rejected the authorization request")
    try:
        payload = response.json()
    except ValueError as error:
        raise LinkedInExchangeError("LinkedIn returned an invalid response") from error
    if not isinstance(payload, dict):
        raise LinkedInExchangeError("LinkedIn returned an invalid response")
    return payload


def _exchange_linkedin_code(code: str) -> ProviderAccountData:
    client_id, client_secret = _linkedin_credentials()
    callback = _callback_url("linkedin")
    try:
        with httpx.Client(timeout=15.0) as client:
            token_response = client.post(
                LINKEDIN_TOKEN_URL,
                data={
                    "grant_type": "authorization_code",
                    "code": code,
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "redirect_uri": callback,
                },
                headers={"Accept": "application/json"},
            )
            token_payload = _linkedin_response_json(token_response)
            access_token = token_payload.get("access_token")
            if not isinstance(access_token, str) or not access_token:
                raise LinkedInExchangeError("LinkedIn did not return an access token")

            profile_response = client.get(
                LINKEDIN_USERINFO_URL,
                headers={
                    "Accept": "application/json",
                    "Authorization": f"Bearer {access_token}",
                },
            )
            profile = _linkedin_response_json(profile_response)
    except httpx.HTTPError as error:
        raise LinkedInExchangeError("LinkedIn could not be reached") from error

    account_id = profile.get("sub")
    if account_id is None:
        raise LinkedInExchangeError("LinkedIn did not return an account identifier")
    display_name = profile.get("name")
    if not display_name:
        display_name = " ".join(
            str(value)
            for value in (profile.get("given_name"), profile.get("family_name"))
            if value
        ).strip()

    expires_at = None
    expires_in = token_payload.get("expires_in")
    if expires_in is not None:
        try:
            lifetime = max(0, int(expires_in))
        except (TypeError, ValueError):
            lifetime = 0
        if lifetime:
            expires_at = datetime.now(timezone.utc) + timedelta(seconds=lifetime)

    refresh_token = token_payload.get("refresh_token")
    return ProviderAccountData(
        provider_account_id=str(account_id),
        account_name=str(display_name or "LinkedIn account"),
        username=None,
        access_token=access_token,
        refresh_token=(
            str(refresh_token) if isinstance(refresh_token, str) and refresh_token else None
        ),
        expires_at=expires_at,
    )


def _mock_account(provider: str, user_id: int, code: str) -> ProviderAccountData:
    return ProviderAccountData(
        provider_account_id=f"local-{provider}-{user_id}",
        account_name=f"Local {provider.title()} account",
        username=f"social9_{provider}_demo",
        access_token=f"{provider}:{code}:{secrets.token_urlsafe(18)}",
        refresh_token=secrets.token_urlsafe(24),
        expires_at=datetime.now(timezone.utc) + timedelta(hours=1),
    )


def _save_account(
    database: Session,
    provider: str,
    user_id: int,
    data: ProviderAccountData,
) -> None:
    account = (
        database.query(SocialAccount)
        .filter(
            SocialAccount.user_id == user_id,
            SocialAccount.provider == provider,
            SocialAccount.provider_account_id == data.provider_account_id,
        )
        .first()
    )
    if account is None:
        account = SocialAccount(
            user_id=user_id,
            provider=provider,
            provider_account_id=data.provider_account_id,
            account_name=data.account_name,
            username=data.username,
            access_token_encrypted=encrypt_token(data.access_token),
            refresh_token_encrypted=(
                encrypt_token(data.refresh_token) if data.refresh_token else None
            ),
            expires_at=data.expires_at,
        )
        database.add(account)
    else:
        account.account_name = data.account_name
        account.username = data.username
        account.status = "connected"
        account.access_token_encrypted = encrypt_token(data.access_token)
        account.refresh_token_encrypted = (
            encrypt_token(data.refresh_token) if data.refresh_token else None
        )
        account.expires_at = data.expires_at
    database.commit()


@router.get("", response_model=list[SocialAccountResponse])
def list_accounts(
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> list[SocialAccount]:
    return (
        database.query(SocialAccount)
        .filter(SocialAccount.user_id == current_user.id)
        .order_by(SocialAccount.created_at.desc())
        .all()
    )


@router.get("/provider-status", response_model=list[ProviderStatusResponse])
def provider_status(
    current_user: User = Depends(get_current_user),
) -> list[ProviderStatusResponse]:
    del current_user
    return [
        ProviderStatusResponse(
            provider=provider,
            mode="preview" if _mock_mode(provider) else "live",
            configured=_provider_configured(provider),
        )
        for provider in sorted(SUPPORTED_PROVIDERS)
    ]


@router.post("/{provider}/connect", response_model=ConnectResponse)
def start_connection(
    provider: str,
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> ConnectResponse:
    provider = provider.lower()
    if provider not in SUPPORTED_PROVIDERS:
        raise HTTPException(status_code=404, detail="Unsupported social provider")

    raw_state = secrets.token_urlsafe(32)
    authorization_url = _authorization_url(provider, raw_state)
    database.add(
        OAuthState(
            user_id=current_user.id,
            provider=provider,
            state_hash=_state_hash(raw_state),
            expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
        )
    )
    database.commit()
    return ConnectResponse(provider=provider, authorization_url=authorization_url)


@router.get("/{provider}/callback", response_class=RedirectResponse)
def oauth_callback(
    provider: str,
    state: str,
    code: str | None = None,
    error: str | None = None,
    database: Session = Depends(get_db),
) -> RedirectResponse:
    provider = provider.lower()
    if provider not in SUPPORTED_PROVIDERS:
        raise HTTPException(status_code=404, detail="Unsupported social provider")
    oauth_state = (
        database.query(OAuthState)
        .filter(
            OAuthState.provider == provider,
            OAuthState.state_hash == _state_hash(state),
        )
        .first()
    )
    now = datetime.now(timezone.utc)
    if oauth_state is None:
        raise HTTPException(status_code=400, detail="Invalid or already-used OAuth state")

    expires_at = oauth_state.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at <= now:
        database.delete(oauth_state)
        database.commit()
        raise HTTPException(status_code=400, detail="OAuth state has expired")

    oauth_user_id = oauth_state.user_id
    database.delete(oauth_state)
    database.commit()

    if error:
        return RedirectResponse(
            _accounts_redirect(error=f"{provider}_access_denied"), status_code=303
        )
    if not code:
        raise HTTPException(status_code=400, detail="Authorization code is missing")

    if _mock_mode(provider):
        account_data = _mock_account(provider, oauth_user_id, code)
    elif provider == "instagram":
        try:
            account_data = _exchange_instagram_code(code)
        except InstagramExchangeError:
            return RedirectResponse(
                _accounts_redirect(error="instagram_auth_failed"), status_code=303
            )
    else:
        try:
            account_data = _exchange_linkedin_code(code)
        except LinkedInExchangeError:
            return RedirectResponse(
                _accounts_redirect(error="linkedin_auth_failed"), status_code=303
            )

    _save_account(database, provider, oauth_user_id, account_data)
    return RedirectResponse(_accounts_redirect(connected=provider), status_code=303)


@router.delete("/{account_id}", status_code=status.HTTP_204_NO_CONTENT)
def disconnect_account(
    account_id: int,
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> None:
    account = (
        database.query(SocialAccount)
        .filter(
            SocialAccount.id == account_id,
            SocialAccount.user_id == current_user.id,
        )
        .first()
    )
    if account is None:
        raise HTTPException(status_code=404, detail="Connected account not found")
    database.delete(account)
    database.commit()
