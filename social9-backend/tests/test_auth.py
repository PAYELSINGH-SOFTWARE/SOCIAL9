import os
import base64
import hashlib
import hmac
import json
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qs, urlparse

os.environ["DATABASE_URL"] = "sqlite:///./test_social9.db"
os.environ["SEED_DEMO_USER"] = "true"
os.environ["EXPOSE_DEV_AUTH_TOKENS"] = "true"
os.environ["OAUTH_MOCK_MODE"] = "true"
os.environ["INSTAGRAM_OAUTH_MOCK_MODE"] = "true"
os.environ["LINKEDIN_OAUTH_MOCK_MODE"] = "true"
os.environ["BILLING_MOCK_MODE"] = "true"
os.environ["FRONTEND_URL"] = "http://localhost:3000"

import pytest
import httpx
from fastapi.testclient import TestClient

from app.database import Base, SessionLocal, engine
from app.encryption import decrypt_token, encrypt_token
from app.main import app, configured_cors_origins
from app.models import Post, SocialAccount
from app import media_storage as media_storage_module
from app import analytics as analytics_module
from app import instagram_insights as instagram_insights_module
from app import publishing as publishing_module
from app import social_accounts as social_accounts_module


def test_production_frontends_are_trusted_cors_origins():
    origins = configured_cors_origins()
    assert "https://social9-web.vercel.app" in origins
    assert not any("chatgpt.site" in origin for origin in origins)


@pytest.fixture(autouse=True)
def reset_database():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)


def test_demo_user_can_login_and_read_profile():
    with TestClient(app) as client:
        login_response = client.post(
            "/auth/login",
            json={"email": "demo@social9.in", "password": "Social9Demo!"},
        )
        assert login_response.status_code == 200
        token = login_response.json()["access_token"]

        profile_response = client.get(
            "/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert profile_response.status_code == 200
        assert profile_response.json()["email"] == "demo@social9.in"


def test_login_rejects_an_invalid_password():
    with TestClient(app) as client:
        response = client.post(
            "/auth/login",
            json={"email": "demo@social9.in", "password": "not-the-password"},
        )
        assert response.status_code == 401


def test_signup_requires_email_verification_before_login():
    with TestClient(app) as client:
        signup_response = client.post(
            "/auth/signup",
            json={
                "name": "New Business",
                "email": "owner@example.com",
                "password": "SecurePass123!",
            },
        )
        assert signup_response.status_code == 201
        assert signup_response.json()["user"]["is_verified"] is False
        token = signup_response.json()["verification_token"]
        assert token

        blocked_login = client.post(
            "/auth/login",
            json={"email": "owner@example.com", "password": "SecurePass123!"},
        )
        assert blocked_login.status_code == 403

        verify_response = client.post("/auth/verify-email", json={"token": token})
        assert verify_response.status_code == 200

        login_response = client.post(
            "/auth/login",
            json={"email": "owner@example.com", "password": "SecurePass123!"},
        )
        assert login_response.status_code == 200
        assert login_response.json()["user"]["is_verified"] is True


def test_password_can_be_reset_with_a_short_lived_token():
    with TestClient(app) as client:
        forgot_response = client.post(
            "/auth/password/forgot", json={"email": "demo@social9.in"}
        )
        assert forgot_response.status_code == 200
        token = forgot_response.json()["token"]
        assert token

        reset_response = client.post(
            "/auth/password/reset",
            json={"token": token, "new_password": "UpdatedDemo123!"},
        )
        assert reset_response.status_code == 200

        reused_token_response = client.post(
            "/auth/password/reset",
            json={"token": token, "new_password": "ThirdPassword123!"},
        )
        assert reused_token_response.status_code == 400

        login_response = client.post(
            "/auth/login",
            json={"email": "demo@social9.in", "password": "UpdatedDemo123!"},
        )
        assert login_response.status_code == 200


def _login_headers(client: TestClient) -> dict[str, str]:
    login_response = client.post(
        "/auth/login",
        json={"email": "demo@social9.in", "password": "Social9Demo!"},
    )
    return {"Authorization": f"Bearer {login_response.json()['access_token']}"}


def _meta_signed_request(provider_user_id: str, secret: str) -> str:
    payload = base64.urlsafe_b64encode(
        json.dumps(
            {"algorithm": "HMAC-SHA256", "user_id": provider_user_id},
            separators=(",", ":"),
        ).encode()
    ).rstrip(b"=").decode()
    signature = base64.urlsafe_b64encode(
        hmac.new(secret.encode(), payload.encode(), hashlib.sha256).digest()
    ).rstrip(b"=").decode()
    return f"{signature}.{payload}"


@pytest.mark.parametrize("provider", ["instagram", "linkedin"])
def test_social_account_mock_connection_and_disconnection(provider: str):
    with TestClient(app) as client:
        headers = _login_headers(client)
        connect_response = client.post(
            f"/social-accounts/{provider}/connect", headers=headers
        )
        assert connect_response.status_code == 200
        authorization_url = connect_response.json()["authorization_url"]
        mock_query = parse_qs(urlparse(authorization_url).query)
        assert urlparse(authorization_url).path == "/oauth/mock"
        assert mock_query["provider"] == [provider]

        callback_response = client.get(
            f"/social-accounts/{provider}/callback",
            params={
                "code": f"manager-demo-{provider}",
                "state": mock_query["state"][0],
            },
            follow_redirects=False,
        )
        assert callback_response.status_code == 303
        assert callback_response.headers["location"] == (
            f"http://localhost:3000/accounts?connected={provider}"
        )

        accounts_response = client.get("/social-accounts", headers=headers)
        assert accounts_response.status_code == 200
        accounts = accounts_response.json()
        assert len(accounts) == 1
        assert accounts[0]["provider"] == provider
        assert "access_token" not in accounts[0]
        assert "access_token_encrypted" not in accounts[0]

        database = SessionLocal()
        try:
            stored_account = database.query(SocialAccount).one()
            assert f"manager-demo-{provider}" not in stored_account.access_token_encrypted
            assert f"manager-demo-{provider}" in decrypt_token(
                stored_account.access_token_encrypted
            )
        finally:
            database.close()

        disconnect_response = client.delete(
            f"/social-accounts/{accounts[0]['id']}", headers=headers
        )
        assert disconnect_response.status_code == 204
        assert client.get("/social-accounts", headers=headers).json() == []


def test_oauth_state_is_single_use():
    with TestClient(app) as client:
        headers = _login_headers(client)
        authorization_url = client.post(
            "/social-accounts/instagram/connect", headers=headers
        ).json()["authorization_url"]
        state = parse_qs(urlparse(authorization_url).query)["state"][0]
        callback_url = "/social-accounts/instagram/callback"
        assert client.get(
            callback_url,
            params={"code": "manager-demo-instagram", "state": state},
            follow_redirects=False,
        ).status_code == 303
        reused_response = client.get(
            callback_url,
            params={"code": "manager-demo-instagram", "state": state},
            follow_redirects=False,
        )
        assert reused_response.status_code == 400


@pytest.mark.parametrize("provider", ["instagram", "linkedin"])
def test_mock_oauth_cancellation_returns_to_accounts(provider: str):
    with TestClient(app) as client:
        headers = _login_headers(client)
        authorization_url = client.post(
            f"/social-accounts/{provider}/connect", headers=headers
        ).json()["authorization_url"]
        state = parse_qs(urlparse(authorization_url).query)["state"][0]

        denied = client.get(
            f"/social-accounts/{provider}/callback",
            params={"error": "access_denied", "state": state},
            follow_redirects=False,
        )
        assert denied.status_code == 303
        assert denied.headers["location"] == (
            f"http://localhost:3000/accounts?error={provider}_access_denied"
        )


def test_provider_status_reports_live_and_preview_modes(monkeypatch):
    monkeypatch.setenv("INSTAGRAM_OAUTH_MOCK_MODE", "false")
    monkeypatch.setenv("INSTAGRAM_CLIENT_ID", "instagram-client-id")
    monkeypatch.setenv("INSTAGRAM_CLIENT_SECRET", "instagram-client-secret")
    monkeypatch.setenv("LINKEDIN_OAUTH_MOCK_MODE", "true")

    with TestClient(app) as client:
        response = client.get("/social-accounts/provider-status", headers=_login_headers(client))

    assert response.status_code == 200
    statuses = {item["provider"]: item for item in response.json()}
    assert statuses["instagram"] == {
        "provider": "instagram",
        "mode": "live",
        "configured": True,
    }
    assert statuses["linkedin"]["mode"] == "preview"


def test_instagram_live_callback_stores_encrypted_long_lived_token(monkeypatch):
    monkeypatch.setenv("INSTAGRAM_OAUTH_MOCK_MODE", "false")
    monkeypatch.setenv("INSTAGRAM_CLIENT_ID", "instagram-client-id")
    monkeypatch.setenv("INSTAGRAM_CLIENT_SECRET", "instagram-client-secret")
    monkeypatch.setenv(
        "INSTAGRAM_REDIRECT_URI",
        "http://localhost:8000/social-accounts/instagram/callback",
    )
    expires_at = datetime.now(timezone.utc) + timedelta(days=60)
    monkeypatch.setattr(
        social_accounts_module,
        "_exchange_instagram_code",
        lambda code: social_accounts_module.ProviderAccountData(
            provider_account_id="17841400000000000",
            account_name="Social9 Studio",
            username="social9studio",
            access_token=f"long-lived-token-for:{code}",
            refresh_token=None,
            expires_at=expires_at,
        ),
    )

    with TestClient(app) as client:
        headers = _login_headers(client)
        connect_response = client.post(
            "/social-accounts/instagram/connect", headers=headers
        )
        assert connect_response.status_code == 200
        authorization_url = connect_response.json()["authorization_url"]
        query = parse_qs(urlparse(authorization_url).query)
        assert urlparse(authorization_url).netloc == "www.instagram.com"
        assert query["client_id"] == ["instagram-client-id"]
        assert query["scope"] == [
            "instagram_business_basic,instagram_business_content_publish,instagram_business_manage_insights"
        ]
        assert query["enable_fb_login"] == ["false"]
        assert query["force_reauth"] == ["true"]
        assert "force_authentication" not in query

        callback = client.get(
            "/social-accounts/instagram/callback",
            params={"code": "provider-code", "state": query["state"][0]},
            follow_redirects=False,
        )
        assert callback.status_code == 303
        assert callback.headers["location"] == (
            "http://localhost:3000/accounts?connected=instagram"
        )

        account_response = client.get("/social-accounts", headers=headers)
        account = account_response.json()[0]
        assert account["provider_account_id"] == "17841400000000000"
        assert account["account_name"] == "Social9 Studio"
        assert account["username"] == "social9studio"
        assert "access_token" not in account

        database = SessionLocal()
        try:
            stored_account = database.query(SocialAccount).one()
            assert stored_account.access_token_encrypted != "long-lived-token-for:provider-code"
            assert decrypt_token(stored_account.access_token_encrypted) == (
                "long-lived-token-for:provider-code"
            )
            assert stored_account.refresh_token_encrypted is None
        finally:
            database.close()


def test_instagram_denial_returns_to_accounts_and_consumes_state(monkeypatch):
    monkeypatch.setenv("INSTAGRAM_OAUTH_MOCK_MODE", "false")
    monkeypatch.setenv("INSTAGRAM_CLIENT_ID", "instagram-client-id")

    with TestClient(app) as client:
        headers = _login_headers(client)
        authorization_url = client.post(
            "/social-accounts/instagram/connect", headers=headers
        ).json()["authorization_url"]
        state = parse_qs(urlparse(authorization_url).query)["state"][0]

        denied = client.get(
            "/social-accounts/instagram/callback",
            params={"error": "access_denied", "state": state},
            follow_redirects=False,
        )
        assert denied.status_code == 303
        assert denied.headers["location"] == (
            "http://localhost:3000/accounts?error=instagram_access_denied"
        )
        assert client.get(
            "/social-accounts/instagram/callback",
            params={"code": "reused", "state": state},
        ).status_code == 400


def test_instagram_code_exchange_uses_meta_token_chain(monkeypatch):
    monkeypatch.setenv("INSTAGRAM_CLIENT_ID", "instagram-client-id")
    monkeypatch.setenv("INSTAGRAM_CLIENT_SECRET", "instagram-client-secret")
    monkeypatch.setenv(
        "INSTAGRAM_REDIRECT_URI",
        "https://api.example.com/social-accounts/instagram/callback",
    )
    real_client = httpx.Client

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "api.instagram.com":
            form = parse_qs(request.content.decode())
            assert request.method == "POST"
            assert form["grant_type"] == ["authorization_code"]
            assert form["code"] == ["authorization-code"]
            assert form["redirect_uri"] == [
                "https://api.example.com/social-accounts/instagram/callback"
            ]
            return httpx.Response(
                200,
                json={"access_token": "short-token", "user_id": 17841400000000000},
            )
        if request.url.path == "/access_token":
            assert request.url.params["grant_type"] == "ig_exchange_token"
            assert request.url.params["access_token"] == "short-token"
            return httpx.Response(
                200,
                json={"access_token": "long-token", "expires_in": 5184000},
            )
        if request.url.path == "/me":
            assert request.url.params["access_token"] == "long-token"
            return httpx.Response(
                200,
                json={
                    "user_id": "17841400000000000",
                    "username": "social9studio",
                    "name": "Social9 Studio",
                    "account_type": "BUSINESS",
                },
            )
        return httpx.Response(404)

    transport = httpx.MockTransport(handler)
    monkeypatch.setattr(
        social_accounts_module.httpx,
        "Client",
        lambda **_: real_client(transport=transport),
    )

    result = social_accounts_module._exchange_instagram_code("authorization-code")
    assert result.provider_account_id == "17841400000000000"
    assert result.username == "social9studio"
    assert result.account_name == "Social9 Studio"
    assert result.access_token == "long-token"
    assert result.refresh_token is None
    assert result.expires_at is not None


def test_linkedin_live_callback_stores_encrypted_access_token(monkeypatch):
    monkeypatch.setenv("LINKEDIN_OAUTH_MOCK_MODE", "false")
    monkeypatch.setenv("LINKEDIN_CLIENT_ID", "linkedin-client-id")
    monkeypatch.setenv("LINKEDIN_CLIENT_SECRET", "linkedin-client-secret")
    monkeypatch.setenv(
        "LINKEDIN_REDIRECT_URI",
        "http://localhost:8000/social-accounts/linkedin/callback",
    )
    expires_at = datetime.now(timezone.utc) + timedelta(days=60)
    monkeypatch.setattr(
        social_accounts_module,
        "_exchange_linkedin_code",
        lambda code: social_accounts_module.ProviderAccountData(
            provider_account_id="linkedin-member-id",
            account_name="Social9 Member",
            username=None,
            access_token=f"linkedin-access-token-for:{code}",
            refresh_token="linkedin-refresh-token",
            expires_at=expires_at,
        ),
    )

    with TestClient(app) as client:
        headers = _login_headers(client)
        connect_response = client.post(
            "/social-accounts/linkedin/connect", headers=headers
        )
        assert connect_response.status_code == 200
        authorization_url = connect_response.json()["authorization_url"]
        query = parse_qs(urlparse(authorization_url).query)
        assert urlparse(authorization_url).netloc == "www.linkedin.com"
        assert query["client_id"] == ["linkedin-client-id"]
        assert query["scope"] == ["openid profile email w_member_social"]

        callback = client.get(
            "/social-accounts/linkedin/callback",
            params={"code": "provider-code", "state": query["state"][0]},
            follow_redirects=False,
        )
        assert callback.status_code == 303
        assert callback.headers["location"] == (
            "http://localhost:3000/accounts?connected=linkedin"
        )

        account = client.get("/social-accounts", headers=headers).json()[0]
        assert account["provider"] == "linkedin"
        assert account["provider_account_id"] == "linkedin-member-id"
        assert account["account_name"] == "Social9 Member"
        assert account["username"] is None

        database = SessionLocal()
        try:
            stored_account = database.query(SocialAccount).one()
            assert stored_account.access_token_encrypted != (
                "linkedin-access-token-for:provider-code"
            )
            assert decrypt_token(stored_account.access_token_encrypted) == (
                "linkedin-access-token-for:provider-code"
            )
            assert decrypt_token(stored_account.refresh_token_encrypted) == (
                "linkedin-refresh-token"
            )
        finally:
            database.close()


def test_linkedin_code_exchange_uses_oidc_userinfo(monkeypatch):
    monkeypatch.setenv("LINKEDIN_CLIENT_ID", "linkedin-client-id")
    monkeypatch.setenv("LINKEDIN_CLIENT_SECRET", "linkedin-client-secret")
    monkeypatch.setenv(
        "LINKEDIN_REDIRECT_URI",
        "https://api.example.com/social-accounts/linkedin/callback",
    )
    real_client = httpx.Client

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "www.linkedin.com":
            form = parse_qs(request.content.decode())
            assert request.method == "POST"
            assert request.url.path == "/oauth/v2/accessToken"
            assert form["grant_type"] == ["authorization_code"]
            assert form["code"] == ["authorization-code"]
            assert form["client_id"] == ["linkedin-client-id"]
            assert form["client_secret"] == ["linkedin-client-secret"]
            assert form["redirect_uri"] == [
                "https://api.example.com/social-accounts/linkedin/callback"
            ]
            return httpx.Response(
                200,
                json={
                    "access_token": "linkedin-access-token",
                    "expires_in": 5184000,
                    "refresh_token": "linkedin-refresh-token",
                },
            )
        if request.url.host == "api.linkedin.com":
            assert request.method == "GET"
            assert request.url.path == "/v2/userinfo"
            assert request.headers["Authorization"] == "Bearer linkedin-access-token"
            return httpx.Response(
                200,
                json={
                    "sub": "linkedin-member-id",
                    "name": "Social9 Member",
                    "given_name": "Social9",
                    "family_name": "Member",
                    "email": "member@example.com",
                },
            )
        return httpx.Response(404)

    transport = httpx.MockTransport(handler)
    monkeypatch.setattr(
        social_accounts_module.httpx,
        "Client",
        lambda **_: real_client(transport=transport),
    )

    result = social_accounts_module._exchange_linkedin_code("authorization-code")
    assert result.provider_account_id == "linkedin-member-id"
    assert result.account_name == "Social9 Member"
    assert result.username is None
    assert result.access_token == "linkedin-access-token"
    assert result.refresh_token == "linkedin-refresh-token"
    assert result.expires_at is not None


def test_linkedin_provider_failure_returns_to_accounts(monkeypatch):
    monkeypatch.setenv("LINKEDIN_OAUTH_MOCK_MODE", "false")
    monkeypatch.setenv("LINKEDIN_CLIENT_ID", "linkedin-client-id")
    monkeypatch.setenv("LINKEDIN_CLIENT_SECRET", "linkedin-client-secret")
    monkeypatch.setattr(
        social_accounts_module,
        "_exchange_linkedin_code",
        lambda code: (_ for _ in ()).throw(
            social_accounts_module.LinkedInExchangeError("provider rejected code")
        ),
    )

    with TestClient(app) as client:
        headers = _login_headers(client)
        authorization_url = client.post(
            "/social-accounts/linkedin/connect", headers=headers
        ).json()["authorization_url"]
        state = parse_qs(urlparse(authorization_url).query)["state"][0]

        callback = client.get(
            "/social-accounts/linkedin/callback",
            params={"code": "provider-code", "state": state},
            follow_redirects=False,
        )
        assert callback.status_code == 303
        assert callback.headers["location"] == (
            "http://localhost:3000/accounts?error=linkedin_auth_failed"
        )
        assert client.get(
            "/social-accounts/linkedin/callback",
            params={"code": "reused-code", "state": state},
        ).status_code == 400


def test_user_can_save_schedule_list_and_delete_posts(tmp_path, monkeypatch):
    monkeypatch.setattr(media_storage_module, "UPLOADS_DIRECTORY", tmp_path)
    with TestClient(app) as client:
        headers = _login_headers(client)
        draft_response = client.post(
            "/posts",
            headers=headers,
            json={
                "caption": "A new local business update",
                "platforms": ["instagram", "linkedin"],
                "media": [{"name": "photo.png", "data": "aGVsbG8="}],
            },
        )
        assert draft_response.status_code == 201
        assert draft_response.json()["status"] == "draft"
        assert len(draft_response.json()["media_urls"]) == 1

        scheduled_response = client.post(
            "/posts",
            headers=headers,
            json={
                "caption": "Tomorrow's scheduled update",
                "platforms": ["linkedin"],
                "scheduled_for": "2099-01-01T10:00:00Z",
            },
        )
        assert scheduled_response.status_code == 201
        assert scheduled_response.json()["status"] == "scheduled"

        assert len(client.get("/posts", headers=headers).json()) == 2
        scheduled_posts = client.get("/posts?status=scheduled", headers=headers).json()
        assert len(scheduled_posts) == 1

        deleted = client.delete(f"/posts/{draft_response.json()['id']}", headers=headers)
        assert deleted.status_code == 204
        assert len(client.get("/posts", headers=headers).json()) == 1
        assert not list(tmp_path.iterdir())


def test_s3_media_storage_returns_a_persistent_public_url(monkeypatch):
    uploads = []

    class FakeS3Client:
        def upload_fileobj(self, file_object, bucket, key, ExtraArgs):
            uploads.append((file_object.read(), bucket, key, ExtraArgs))

    monkeypatch.setenv("MEDIA_STORAGE_BACKEND", "s3")
    monkeypatch.setenv("S3_BUCKET", "social9-media")
    monkeypatch.setenv("S3_PUBLIC_BASE_URL", "https://media.example.com")
    monkeypatch.setenv("S3_KEY_PREFIX", "production")
    monkeypatch.setattr(media_storage_module, "_s3_client", lambda: FakeS3Client())

    media_url = media_storage_module.store_media("photo.jpg", b"image-data")

    assert media_url == "https://media.example.com/production/photo.jpg"
    assert uploads[0][0:3] == (b"image-data", "social9-media", "production/photo.jpg")
    assert uploads[0][3]["ContentType"] == "image/jpeg"


def test_meta_deauthorization_removes_the_instagram_connection(monkeypatch):
    secret = "meta-test-secret"
    monkeypatch.setenv("INSTAGRAM_CLIENT_SECRET", secret)
    with TestClient(app) as client:
        headers = _login_headers(client)
        with SessionLocal() as database:
            database.add(
                SocialAccount(
                    user_id=1,
                    provider="instagram",
                    provider_account_id="ig-review-user",
                    account_name="Review account",
                    status="connected",
                    access_token_encrypted=encrypt_token("token"),
                )
            )
            database.commit()

        response = client.post(
            "/meta/instagram/deauthorize",
            data={"signed_request": _meta_signed_request("ig-review-user", secret)},
        )

        assert response.status_code == 200
        assert response.json() == {"success": True}
        assert client.get("/social-accounts", headers=headers).json() == []


def test_meta_data_deletion_returns_a_verifiable_completion_url(monkeypatch):
    secret = "meta-deletion-secret"
    monkeypatch.setenv("INSTAGRAM_CLIENT_SECRET", secret)
    monkeypatch.setenv("FRONTEND_URL", "https://social9-web.vercel.app")
    with TestClient(app) as client:
        _login_headers(client)
        with SessionLocal() as database:
            database.add(
                SocialAccount(
                    user_id=1,
                    provider="instagram",
                    provider_account_id="ig-delete-user",
                    account_name="Deletion account",
                    status="connected",
                    access_token_encrypted=encrypt_token("token"),
                )
            )
            database.commit()

        response = client.post(
            "/meta/instagram/data-deletion",
            data={"signed_request": _meta_signed_request("ig-delete-user", secret)},
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["url"].startswith("https://social9-web.vercel.app/data-deletion?code=")

        status_response = client.get(
            "/meta/instagram/data-deletion/status",
            params={"code": payload["confirmation_code"]},
        )
        assert status_response.status_code == 200
        assert status_response.json()["status"] == "completed"


def test_meta_compliance_rejects_an_invalid_signature(monkeypatch):
    monkeypatch.setenv("INSTAGRAM_CLIENT_SECRET", "correct-secret")
    with TestClient(app) as client:
        response = client.post(
            "/meta/instagram/deauthorize",
            data={"signed_request": _meta_signed_request("ig-user", "wrong-secret")},
        )
        assert response.status_code == 400


def test_post_validation_rejects_invalid_content_and_past_schedule():
    with TestClient(app) as client:
        headers = _login_headers(client)
        assert client.post(
            "/posts", headers=headers, json={"caption": " ", "platforms": ["linkedin"]}
        ).status_code == 422


def test_calendar_range_reschedule_and_move_to_draft():
    with TestClient(app) as client:
        headers = _login_headers(client)
        created = client.post(
            "/posts",
            headers=headers,
            json={
                "caption": "Calendar campaign",
                "platforms": ["instagram"],
                "scheduled_for": "2099-04-10T10:00:00Z",
            },
        ).json()

        april_posts = client.get(
            "/posts?date_from=2099-04-01T00:00:00Z&date_to=2099-05-01T00:00:00Z",
            headers=headers,
        )
        assert april_posts.status_code == 200
        assert [post["id"] for post in april_posts.json()] == [created["id"]]

        rescheduled = client.patch(
            f"/posts/{created['id']}/schedule",
            headers=headers,
            json={"scheduled_for": "2099-05-12T14:30:00Z"},
        )
        assert rescheduled.status_code == 200
        assert rescheduled.json()["status"] == "scheduled"
        assert client.get(
            "/posts?date_from=2099-04-01T00:00:00Z&date_to=2099-05-01T00:00:00Z",
            headers=headers,
        ).json() == []

        draft = client.patch(f"/posts/{created['id']}/draft", headers=headers)
        assert draft.status_code == 200
        assert draft.json()["status"] == "draft"
        assert draft.json()["scheduled_for"] is None


def test_content_library_can_search_filter_edit_and_duplicate_posts():
    with TestClient(app) as client:
        headers = _login_headers(client)
        first = client.post(
            "/posts",
            headers=headers,
            json={"caption": "September product launch", "platforms": ["linkedin"]},
        ).json()
        client.post(
            "/posts",
            headers=headers,
            json={"caption": "Behind the scenes reel", "platforms": ["instagram"]},
        )

        search = client.get("/posts?search=product&platform=linkedin", headers=headers)
        assert search.status_code == 200
        assert [post["id"] for post in search.json()] == [first["id"]]

        updated = client.patch(
            f"/posts/{first['id']}",
            headers=headers,
            json={
                "caption": "Updated product launch",
                "platforms": ["instagram", "linkedin"],
                "scheduled_for": "2099-09-10T10:00:00Z",
            },
        )
        assert updated.status_code == 200
        assert updated.json()["status"] == "scheduled"
        assert updated.json()["caption"] == "Updated product launch"

        duplicated = client.post(f"/posts/{first['id']}/duplicate", headers=headers)
        assert duplicated.status_code == 201
        assert duplicated.json()["status"] == "draft"
        assert duplicated.json()["scheduled_for"] is None
        assert duplicated.json()["caption"] == "Updated product launch"


def test_action_center_uses_real_workspace_state():
    with TestClient(app) as client:
        headers = _login_headers(client)
        client.post(
            "/posts",
            headers=headers,
            json={
                "caption": "This week's announcement",
                "platforms": ["linkedin"],
                "scheduled_for": (datetime.now(timezone.utc) + timedelta(days=2)).isoformat(),
            },
        )

        response = client.get("/workspace/actions", headers=headers)
        assert response.status_code == 200
        payload = response.json()
        assert payload["summary"]["scheduled_this_week"] == 1
        action_ids = {action["id"] for action in payload["actions"]}
        assert "missing-instagram" in action_ids
        assert "missing-linkedin" in action_ids
        assert "upcoming-week" in action_ids


def test_analytics_are_authenticated_deterministic_and_user_owned():
    with TestClient(app) as client:
        assert client.get("/analytics/summary").status_code in (401, 403)
        headers = _login_headers(client)
        client.post(
            "/posts",
            headers=headers,
            json={"caption": "Analytics sample", "platforms": ["instagram", "linkedin"]},
        )

        first = client.get("/analytics/summary?days=30", headers=headers)
        second = client.get("/analytics/summary?days=30", headers=headers)
        assert first.status_code == 200
        assert first.json() == second.json()
        assert first.json()["simulated"] is False
        assert first.json()["provider_metrics_available"] is False
        assert first.json()["overview"]["total_posts"] == 1
        assert first.json()["overview"]["drafts"] == 1
        assert len(first.json()["trend"]) == 7
        assert {channel["provider"] for channel in first.json()["channels"]} == {
            "instagram",
            "linkedin",
        }
        assert first.json()["recent_posts"][0]["caption"] == "Analytics sample"
        assert first.json()["trend"][-1]["created"] == 1
        assert client.get("/analytics/summary?days=15", headers=headers).status_code == 400
        assert client.post(
            "/posts", headers=headers, json={"caption": "Hello", "platforms": ["facebook"]}
        ).status_code == 422


def test_publishing_consistency_tracks_active_and_at_risk_streaks():
    now = datetime(2026, 9, 3, 12, tzinfo=timezone.utc)
    active_posts = [
        Post(
            id=index,
            owner_id=1,
            caption=f"Week {index}",
            platforms="instagram",
            status="published",
            published_at=now - timedelta(days=offset),
            created_at=now - timedelta(days=offset),
        )
        for index, offset in enumerate((1, 8, 15), start=1)
    ]
    active = analytics_module._publishing_consistency(active_posts, now)
    assert active["current_streak"] == 3
    assert active["longest_streak"] == 3
    assert active["state"] == "active"
    assert active["at_risk"] is False

    previous_posts = active_posts[1:]
    at_risk = analytics_module._publishing_consistency(previous_posts, now)
    assert at_risk["current_streak"] == 2
    assert at_risk["state"] == "at_risk"
    assert at_risk["at_risk"] is True

    previous_posts.append(
        Post(
            id=4,
            owner_id=1,
            caption="Protect the streak",
            platforms="linkedin",
            status="scheduled",
            scheduled_for=now + timedelta(days=1),
            created_at=now,
        )
    )
    protected = analytics_module._publishing_consistency(previous_posts, now)
    assert protected["state"] == "protected"
    assert protected["scheduled_this_week"] == 1


def test_recycling_candidates_prioritize_provider_engagement():
    now = datetime(2026, 9, 4, 12, tzinfo=timezone.utc)
    posts = [
        Post(
            id=1,
            owner_id=1,
            caption="A proven local offer",
            platforms="instagram",
            status="published",
            published_at=now - timedelta(days=30),
            created_at=now - timedelta(days=30),
            external_post_ids=json.dumps({"instagram": "media-1"}),
            media_urls=json.dumps(["https://cdn.example.com/offer.jpg"]),
        ),
        Post(
            id=2,
            owner_id=1,
            caption="Still too recent",
            platforms="linkedin",
            status="published",
            published_at=now - timedelta(days=5),
            created_at=now - timedelta(days=5),
            external_post_ids=json.dumps({"linkedin": "urn:li:share:2"}),
            media_urls="[]",
        ),
    ]
    instagram = {"top_media": [{"id": "media-1", "interactions": 42}]}

    result = analytics_module._recycling_candidates(posts, instagram, now)

    assert result["eligible_count"] == 1
    assert result["candidates"][0]["post_id"] == 1
    assert result["candidates"][0]["interactions"] == 42
    assert result["candidates"][0]["media_url"].endswith("offer.jpg")


def test_publish_now_and_due_scheduler_use_connected_preview_account():
    with TestClient(app) as client:
        headers = _login_headers(client)
        authorization_url = client.post(
            "/social-accounts/linkedin/connect", headers=headers
        ).json()["authorization_url"]
        state = parse_qs(urlparse(authorization_url).query)["state"][0]
        callback = client.get(
            "/social-accounts/linkedin/callback",
            params={"code": "preview-code", "state": state},
            follow_redirects=False,
        )
        assert callback.status_code == 303

        draft = client.post(
            "/posts",
            headers=headers,
            json={"caption": "Publish this now", "platforms": ["linkedin"]},
        ).json()
        published = client.post(f"/posts/{draft['id']}/publish", headers=headers)
        assert published.status_code == 200
        assert published.json()["status"] == "published"
        assert published.json()["external_post_ids"]["linkedin"].startswith("preview:")
        assert published.json()["published_at"] is not None

        scheduled = client.post(
            "/posts",
            headers=headers,
            json={
                "caption": "Publish this when due",
                "platforms": ["linkedin"],
                "scheduled_for": "2099-01-01T10:00:00Z",
            },
        ).json()
        database = SessionLocal()
        try:
            post = database.query(Post).filter(Post.id == scheduled["id"]).one()
            post.scheduled_for = datetime.now(timezone.utc) - timedelta(minutes=1)
            database.commit()
            assert publishing_module.process_due_posts(database) == 1
            database.refresh(post)
            assert post.status == "published"
        finally:
            database.close()
        assert client.post(
            "/posts",
            headers=headers,
            json={
                "caption": "Too late",
                "platforms": ["instagram"],
                "scheduled_for": "2020-01-01T10:00:00Z",
            },
        ).status_code == 422


def test_linkedin_and_instagram_publishers_send_provider_requests(tmp_path, monkeypatch):
    linkedin_account = SocialAccount(
        id=10,
        user_id=1,
        provider="linkedin",
        provider_account_id="member-123",
        account_name="LinkedIn Member",
        status="connected",
        access_token_encrypted=encrypt_token("linkedin-token"),
    )

    def linkedin_handler(request: httpx.Request) -> httpx.Response:
        assert str(request.url) == publishing_module.LINKEDIN_POSTS_URL
        assert request.headers["authorization"] == "Bearer linkedin-token"
        assert b'"commentary":"Provider test"' in request.content
        return httpx.Response(201, headers={"x-restli-id": "urn:li:share:123"})

    with httpx.Client(transport=httpx.MockTransport(linkedin_handler)) as provider_client:
        external_id = publishing_module.publish_linkedin(
            linkedin_account, "Provider test", [], provider_client
        )
    assert external_id == "urn:li:share:123"

    monkeypatch.setattr(media_storage_module, "UPLOADS_DIRECTORY", tmp_path)
    (tmp_path / "photo.png").write_bytes(b"image-data")
    instagram_account = SocialAccount(
        id=11,
        user_id=1,
        provider="instagram",
        provider_account_id="ig-456",
        account_name="Instagram Business",
        status="connected",
        access_token_encrypted=encrypt_token("instagram-token"),
    )
    requests = []

    def instagram_handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.method == "GET":
            return httpx.Response(200, json={"status_code": "FINISHED"})
        if request.url.path.endswith("/media_publish"):
            return httpx.Response(200, json={"id": "ig-post-789"})
        return httpx.Response(200, json={"id": "container-789"})

    with httpx.Client(transport=httpx.MockTransport(instagram_handler)) as provider_client:
        external_id = publishing_module.publish_instagram(
            instagram_account, "Instagram test", ["/uploads/photo.png"], provider_client
        )
    assert external_id == "ig-post-789"
    assert len(requests) == 3
    assert requests[0].url.path.endswith("/ig-456/media")
    assert requests[1].url.path.endswith("/container-789")
    assert requests[2].url.path.endswith("/ig-456/media_publish")


def test_instagram_publisher_refreshes_an_expiring_token(tmp_path, monkeypatch):
    monkeypatch.setattr(media_storage_module, "UPLOADS_DIRECTORY", tmp_path)
    (tmp_path / "photo.png").write_bytes(b"image-data")
    account = SocialAccount(
        id=12,
        user_id=1,
        provider="instagram",
        provider_account_id="ig-refresh",
        account_name="Instagram Business",
        status="connected",
        access_token_encrypted=encrypt_token("expiring-token"),
        expires_at=datetime.now(timezone.utc) + timedelta(days=3),
    )
    requests = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.path == "/refresh_access_token":
            assert request.url.params["grant_type"] == "ig_refresh_token"
            assert request.url.params["access_token"] == "expiring-token"
            return httpx.Response(
                200,
                json={"access_token": "refreshed-token", "expires_in": 5184000},
            )
        if request.method == "GET":
            assert request.url.params["access_token"] == "refreshed-token"
            return httpx.Response(200, json={"status_code": "FINISHED"})
        form = parse_qs(request.content.decode())
        if request.url.path.endswith("/media_publish"):
            assert form["access_token"] == ["refreshed-token"]
            return httpx.Response(200, json={"id": "ig-post-refreshed"})
        assert form["access_token"] == ["refreshed-token"]
        return httpx.Response(200, json={"id": "container-refreshed"})

    with httpx.Client(transport=httpx.MockTransport(handler)) as provider_client:
        external_id = publishing_module.publish_instagram(
            account, "Refresh test", ["/uploads/photo.png"], provider_client
        )

    assert external_id == "ig-post-refreshed"
    assert len(requests) == 4
    assert decrypt_token(account.access_token_encrypted) == "refreshed-token"
    assert account.expires_at is not None
    assert account.expires_at > datetime.now(timezone.utc) + timedelta(days=59)


def test_instagram_insights_reads_account_and_media_metrics():
    account = SocialAccount(
        id=13,
        user_id=1,
        provider="instagram",
        provider_account_id="ig-insights",
        account_name="Insights account",
        username="social9test",
        status="connected",
        access_token_encrypted=encrypt_token("insights-token"),
    )
    requests = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        assert request.url.params["access_token"] == "insights-token"
        if request.url.path.endswith("/ig-insights"):
            assert request.url.params["fields"] == (
                "id,username,name,followers_count,media_count"
            )
            return httpx.Response(
                200,
                json={
                    "id": "ig-insights",
                    "username": "social9test",
                    "name": "Insights account",
                    "followers_count": 940,
                    "media_count": 82,
                },
            )
        if request.url.path.endswith("/insights"):
            assert request.url.params["period"] == "day"
            metrics = request.url.params["metric"].split(",")
            values = {
                "reach": 120,
                "profile_views": 18,
                "views": 310,
                "follower_count": 7,
                "total_interactions": 24,
                "likes": 19,
                "comments": 3,
                "shares": 1,
                "saves": 1,
            }
            return httpx.Response(
                200,
                json={
                    "data": [
                        {
                            "name": metric,
                            "values": [
                                {
                                    "value": values[metric],
                                    "end_time": "2026-09-03T00:00:00+0000",
                                }
                            ],
                        }
                        for metric in metrics
                    ]
                },
            )
        assert request.url.path.endswith("/media")
        return httpx.Response(
            200,
            json={
                "data": [
                    {
                        "id": "media-1",
                        "caption": "A real provider post",
                        "media_type": "IMAGE",
                        "permalink": "https://www.instagram.com/p/example/",
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                        "like_count": 14,
                        "comments_count": 3,
                    }
                ]
            },
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as provider_client:
        metrics = instagram_insights_module._account_insights(
            account, 30, provider_client
        )

    assert metrics["reach"] == 120
    assert metrics["impressions"] == 310
    assert metrics["profile_views"] == 18
    assert metrics["followers"] == 940
    assert metrics["followers_gained"] == 7
    assert metrics["media_count"] == 82
    assert metrics["likes"] == 14
    assert metrics["comments"] == 3
    assert metrics["shares"] == 1
    assert metrics["saves"] == 1
    assert metrics["interactions"] == 24
    assert metrics["engagement_rate"] == 20
    assert metrics["media"][0]["interactions"] == 17
    assert metrics["unavailable_metrics"] == []
    assert len(requests) == 6


def test_instagram_media_paginates_and_stops_after_the_requested_range():
    now = datetime.now(timezone.utc)
    pages = []

    def media_item(media_id: str, days_old: int) -> dict:
        return {
            "id": media_id,
            "caption": media_id,
            "media_product_type": "REELS",
            "timestamp": (now - timedelta(days=days_old)).isoformat(),
            "like_count": 5,
            "comments_count": 2,
        }

    def handler(request: httpx.Request) -> httpx.Response:
        pages.append(request)
        if request.url.params.get("after") == "page-two":
            return httpx.Response(
                200,
                json={"data": [media_item("recent-2", 8), media_item("old", 45)]},
            )
        return httpx.Response(
            200,
            json={
                "data": [media_item("recent-1", 2)],
                "paging": {"cursors": {"after": "page-two"}},
            },
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as provider_client:
        media = instagram_insights_module._account_media(
            "https://graph.instagram.com/v23.0/ig-insights",
            "insights-token",
            now - timedelta(days=30),
            provider_client,
        )

    assert [item["id"] for item in media] == ["recent-1", "recent-2"]
    assert pages[1].url.params["after"] == "page-two"
    assert len(pages) == 2


def test_growth_projection_is_locked_until_subscription_is_active():
    with TestClient(app) as client:
        assert client.get("/billing/subscription").status_code in (401, 403)
        headers = _login_headers(client)

        free_subscription = client.get("/billing/subscription", headers=headers)
        assert free_subscription.status_code == 200
        assert free_subscription.json()["plan"] == "free"
        assert free_subscription.json()["is_paid"] is False
        assert free_subscription.json()["features"]["growth_projection"] is False
        assert client.get(
            "/billing/features/growth-projection/access", headers=headers
        ).status_code == 402

        subscribed = client.post("/billing/mock/subscribe", headers=headers)
        assert subscribed.status_code == 200
        assert subscribed.json()["plan"] == "pro"
        assert subscribed.json()["status"] == "active"
        assert subscribed.json()["features"]["growth_projection"] is True

        access = client.get(
            "/billing/features/growth-projection/access", headers=headers
        )
        assert access.status_code == 200
        assert access.json() == {"feature": "growth_projection", "allowed": True}

        canceled = client.post("/billing/mock/cancel", headers=headers)
        assert canceled.status_code == 200
        assert canceled.json()["status"] == "canceled"
        assert canceled.json()["features"]["growth_projection"] is False
        assert client.get(
            "/billing/features/growth-projection/access", headers=headers
        ).status_code == 402


def test_ai_assistant_is_authenticated_and_returns_preview_content():
    with TestClient(app) as client:
        assert client.post(
            "/ai/assist", json={"action": "caption", "topic": "a weekend offer"}
        ).status_code in (401, 403)
        headers = _login_headers(client)
        response = client.post(
            "/ai/assist",
            headers=headers,
            json={"action": "caption", "topic": "a weekend offer", "platform": "instagram"},
        )
        assert response.status_code == 200
        assert response.json()["simulated"] is True
        assert "weekend offer" in response.json()["content"]
        assert len(response.json()["suggestions"]) == 3
        assert client.post(
            "/ai/assist", headers=headers, json={"action": "caption", "topic": "x"}
        ).status_code == 422
