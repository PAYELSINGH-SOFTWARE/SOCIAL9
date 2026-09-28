import json
import os
import time
from datetime import datetime, timedelta, timezone

import httpx
from sqlalchemy.orm import Session

from .encryption import decrypt_token, encrypt_token
from .media_storage import MediaStorageError, media_extension, public_media_url, read_media_bytes
from .models import Post, SocialAccount


LINKEDIN_POSTS_URL = "https://api.linkedin.com/rest/posts"
LINKEDIN_IMAGES_URL = "https://api.linkedin.com/rest/images?action=initializeUpload"
INSTAGRAM_GRAPH_URL = "https://graph.instagram.com"
INSTAGRAM_REFRESH_WINDOW = timedelta(days=7)
INSTAGRAM_CONTAINER_POLL_ATTEMPTS = 10
INSTAGRAM_CONTAINER_POLL_INTERVAL_SECONDS = 1.5


class PublishError(RuntimeError):
    """A safe publishing error suitable for displaying to the post owner."""


def _linkedin_headers(access_token: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {access_token}",
        "Linkedin-Version": os.getenv("LINKEDIN_API_VERSION", "202606"),
        "X-Restli-Protocol-Version": "2.0.0",
        "Content-Type": "application/json",
    }


def _provider_error(response: httpx.Response, provider: str) -> PublishError:
    detail = ""
    try:
        payload = response.json()
        if isinstance(payload, dict):
            error = payload.get("error")
            if isinstance(error, dict):
                detail = str(error.get("error_user_msg") or error.get("message") or "")
            detail = detail or str(payload.get("message") or payload.get("error_description") or "")
    except ValueError:
        pass
    suffix = f": {detail[:240]}" if detail else ""
    return PublishError(f"{provider} rejected the post ({response.status_code}){suffix}")


def _wait_for_instagram_container(creation_id: str, access_token: str, client: httpx.Client) -> None:
    """Wait until Instagram has finished downloading and processing uploaded media."""
    for attempt in range(INSTAGRAM_CONTAINER_POLL_ATTEMPTS):
        response = client.get(
            f"{INSTAGRAM_GRAPH_URL}/{creation_id}",
            params={"fields": "status_code,status", "access_token": access_token},
        )
        if not response.is_success:
            raise _provider_error(response, "Instagram")
        try:
            payload = response.json()
            status_code = str(payload.get("status_code") or "").upper()
            status_detail = str(payload.get("status") or "")
        except (TypeError, ValueError) as error:
            raise PublishError("Instagram returned an invalid media-processing response") from error
        if status_code == "FINISHED":
            return
        if status_code in {"ERROR", "EXPIRED"}:
            suffix = f": {status_detail[:240]}" if status_detail else ""
            raise PublishError(f"Instagram could not process the uploaded image{suffix}")
        if attempt < INSTAGRAM_CONTAINER_POLL_ATTEMPTS - 1:
            time.sleep(INSTAGRAM_CONTAINER_POLL_INTERVAL_SECONDS)
    raise PublishError("Instagram is still processing the image; try publishing again shortly")


def _instagram_access_token(account: SocialAccount, client: httpx.Client) -> str:
    try:
        access_token = decrypt_token(account.access_token_encrypted)
    except ValueError as error:
        raise PublishError("Reconnect Instagram before publishing") from error

    expires_at = account.expires_at
    if expires_at is None:
        return access_token
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at - datetime.now(timezone.utc) > INSTAGRAM_REFRESH_WINDOW:
        return access_token

    response = client.get(
        f"{INSTAGRAM_GRAPH_URL}/refresh_access_token",
        params={
            "grant_type": "ig_refresh_token",
            "access_token": access_token,
        },
        headers={"Accept": "application/json"},
    )
    if not response.is_success:
        raise PublishError("Reconnect Instagram before publishing")
    try:
        payload = response.json()
        refreshed_token = payload["access_token"]
        expires_in = int(payload.get("expires_in", 60 * 24 * 60 * 60))
    except (KeyError, TypeError, ValueError) as error:
        raise PublishError("Instagram returned an invalid token refresh response") from error
    if not isinstance(refreshed_token, str) or not refreshed_token:
        raise PublishError("Instagram returned an invalid token refresh response")

    account.access_token_encrypted = encrypt_token(refreshed_token)
    account.expires_at = datetime.now(timezone.utc) + timedelta(seconds=max(0, expires_in))
    return refreshed_token


def publish_linkedin(account: SocialAccount, caption: str, media_urls: list[str], client: httpx.Client) -> str:
    if len(media_urls) > 1:
        raise PublishError("LinkedIn multi-image publishing is not supported yet")
    if media_urls and media_extension(media_urls[0]) in {".mp4", ".mov"}:
        raise PublishError("LinkedIn video publishing is not supported yet")
    if account.provider_account_id.startswith("local-linkedin-"):
        return f"preview:linkedin:{account.id}:{int(datetime.now(timezone.utc).timestamp())}"

    try:
        access_token = decrypt_token(account.access_token_encrypted)
    except ValueError as error:
        raise PublishError("Reconnect LinkedIn before publishing") from error
    headers = _linkedin_headers(access_token)
    author = f"urn:li:person:{account.provider_account_id}"
    body: dict = {
        "author": author,
        "commentary": caption,
        "visibility": "PUBLIC",
        "distribution": {"feedDistribution": "MAIN_FEED", "targetEntities": [], "thirdPartyDistributionChannels": []},
        "lifecycleState": "PUBLISHED",
        "isReshareDisabledByAuthor": False,
    }
    if media_urls:
        initialize = client.post(LINKEDIN_IMAGES_URL, headers=headers, json={"initializeUploadRequest": {"owner": author}})
        if not initialize.is_success:
            raise _provider_error(initialize, "LinkedIn")
        try:
            upload = initialize.json()["value"]
            upload_url = upload["uploadUrl"]
            image_urn = upload["image"]
        except (KeyError, TypeError, ValueError) as error:
            raise PublishError("LinkedIn returned an invalid image upload response") from error
        try:
            media_contents, media_type = read_media_bytes(media_urls[0], client)
        except MediaStorageError as error:
            raise PublishError(str(error)) from error
        upload_response = client.put(
            upload_url,
            headers={"Authorization": f"Bearer {access_token}", "Content-Type": media_type},
            content=media_contents,
        )
        if not upload_response.is_success:
            raise _provider_error(upload_response, "LinkedIn")
        body["content"] = {"media": {"altText": caption[:300], "id": image_urn}}
    response = client.post(LINKEDIN_POSTS_URL, headers=headers, json=body)
    if not response.is_success:
        raise _provider_error(response, "LinkedIn")
    external_id = response.headers.get("x-restli-id")
    if not external_id:
        raise PublishError("LinkedIn published the request but returned no post identifier")
    return external_id


def publish_instagram(account: SocialAccount, caption: str, media_urls: list[str], client: httpx.Client) -> str:
    if len(media_urls) != 1:
        raise PublishError("Instagram publishing currently requires exactly one image")
    extension = media_extension(media_urls[0])
    if extension not in {".jpg", ".jpeg", ".png"}:
        raise PublishError("Instagram publishing currently supports JPG and PNG images")
    if account.provider_account_id.startswith("local-instagram-"):
        return f"preview:instagram:{account.id}:{int(datetime.now(timezone.utc).timestamp())}"
    access_token = _instagram_access_token(account, client)
    version = os.getenv("INSTAGRAM_API_VERSION", "v23.0").strip("/")
    base_url = f"{INSTAGRAM_GRAPH_URL}/{version}/{account.provider_account_id}"
    container = client.post(
        f"{base_url}/media",
        data={"image_url": public_media_url(media_urls[0]), "caption": caption, "access_token": access_token},
    )
    if not container.is_success:
        raise _provider_error(container, "Instagram")
    try:
        creation_id = str(container.json()["id"])
    except (KeyError, TypeError, ValueError) as error:
        raise PublishError("Instagram returned an invalid media response") from error
    _wait_for_instagram_container(creation_id, access_token, client)
    response = client.post(f"{base_url}/media_publish", data={"creation_id": creation_id, "access_token": access_token})
    if not response.is_success:
        raise _provider_error(response, "Instagram")
    try:
        return str(response.json()["id"])
    except (KeyError, TypeError, ValueError) as error:
        raise PublishError("Instagram returned no post identifier") from error


def _connected_accounts(database: Session, post: Post) -> dict[str, SocialAccount]:
    requested = post.platforms.split(",")
    accounts = database.query(SocialAccount).filter(
        SocialAccount.user_id == post.owner_id,
        SocialAccount.status == "connected",
        SocialAccount.provider.in_(requested),
    ).order_by(SocialAccount.updated_at.desc()).all()
    result: dict[str, SocialAccount] = {}
    for account in accounts:
        result.setdefault(account.provider, account)
    missing = [provider for provider in requested if provider not in result]
    if missing:
        raise PublishError(f"Connect {', '.join(provider.title() for provider in missing)} before publishing")
    expired = [provider for provider, account in result.items() if account.expires_at and (account.expires_at if account.expires_at.tzinfo else account.expires_at.replace(tzinfo=timezone.utc)) <= datetime.now(timezone.utc)]
    if expired:
        raise PublishError(f"Reconnect {', '.join(provider.title() for provider in expired)} before publishing")
    return result


def publish_post(database: Session, post: Post) -> Post:
    if post.status == "published":
        return post
    try:
        accounts = _connected_accounts(database, post)
        media_urls = json.loads(post.media_urls or "[]")
        if not isinstance(media_urls, list):
            raise PublishError("The post media data is invalid")
    except PublishError as error:
        post.status = "failed"
        post.publish_error = str(error)
        database.commit()
        database.refresh(post)
        return post

    post.status = "publishing"
    post.publish_error = None
    database.commit()
    try:
        external_ids: dict[str, str] = json.loads(post.external_post_ids or "{}")
    except (TypeError, ValueError):
        external_ids = {}
    try:
        with httpx.Client(timeout=30.0, follow_redirects=True) as client:
            for provider in post.platforms.split(","):
                if provider in external_ids:
                    continue
                account = accounts[provider]
                if provider == "linkedin":
                    external_ids[provider] = publish_linkedin(account, post.caption, media_urls, client)
                elif provider == "instagram":
                    external_ids[provider] = publish_instagram(account, post.caption, media_urls, client)
    except (PublishError, httpx.HTTPError) as error:
        post.status = "failed"
        post.publish_error = str(error) if isinstance(error, PublishError) else "The social provider could not be reached"
        post.external_post_ids = json.dumps(external_ids)
        database.commit()
        database.refresh(post)
        return post

    post.status = "published"
    post.scheduled_for = None
    post.published_at = datetime.now(timezone.utc)
    post.publish_error = None
    post.external_post_ids = json.dumps(external_ids)
    database.commit()
    database.refresh(post)
    return post


def process_due_posts(database: Session) -> int:
    due_posts = database.query(Post).filter(
        Post.status == "scheduled",
        Post.scheduled_for.is_not(None),
        Post.scheduled_for <= datetime.now(timezone.utc),
    ).order_by(Post.scheduled_for.asc()).all()
    for post in due_posts:
        publish_post(database, post)
    return len(due_posts)
