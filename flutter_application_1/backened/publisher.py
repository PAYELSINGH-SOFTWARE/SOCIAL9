import json
import mimetypes
import os
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from sqlalchemy.orm import Session

from .models import Post, SocialAccount
from .router.accounts import decrypt_token

LINKEDIN_API_VERSION = os.getenv("LINKEDIN_API_VERSION", "202606")
UPLOADS_DIRECTORY = Path(__file__).resolve().parent / "uploads"


class PublishError(Exception):
    pass


def _linkedin_request(url, token, method="GET", payload=None, raw_body=None, headers=None):
    request_headers = {
        "Authorization": f"Bearer {token}",
        "LinkedIn-Version": LINKEDIN_API_VERSION,
        "X-Restli-Protocol-Version": "2.0.0",
        **(headers or {}),
    }
    body = raw_body
    if payload is not None:
        body = json.dumps(payload).encode()
        request_headers["Content-Type"] = "application/json"
    request = Request(url, data=body, headers=request_headers, method=method)
    try:
        with urlopen(request, timeout=30) as response:
            response_body = response.read()
            try:
                parsed = json.loads(response_body) if response_body else {}
            except json.JSONDecodeError:
                parsed = {}
            return parsed, dict(response.headers)
    except HTTPError as exc:
        provider_body = exc.read().decode(errors="replace")
        try:
            provider_data = json.loads(provider_body)
            message = (
                provider_data.get("message")
                or provider_data.get("error_description")
                or provider_body
            )
        except json.JSONDecodeError:
            message = provider_body or str(exc)
        raise PublishError(f"LinkedIn rejected the post ({exc.code}): {message}") from exc
    except (URLError, TimeoutError) as exc:
        raise PublishError(f"Could not reach LinkedIn: {exc}") from exc


def _upload_linkedin_image(token: str, owner_urn: str, media_url: str) -> str:
    local_path = UPLOADS_DIRECTORY / Path(media_url).name
    if not local_path.is_file():
        raise PublishError("The selected image is no longer available")
    mime_type = mimetypes.guess_type(local_path.name)[0] or "application/octet-stream"
    if not mime_type.startswith("image/"):
        raise PublishError("LinkedIn publishing currently supports text or one image")

    result, _ = _linkedin_request(
        "https://api.linkedin.com/rest/images?action=initializeUpload",
        token,
        method="POST",
        payload={"initializeUploadRequest": {"owner": owner_urn}},
    )
    upload = result.get("value", {})
    upload_url = upload.get("uploadUrl")
    image_urn = upload.get("image")
    if not upload_url or not image_urn:
        raise PublishError("LinkedIn did not provide an image upload destination")

    _linkedin_request(
        upload_url,
        token,
        method="PUT",
        raw_body=local_path.read_bytes(),
        headers={"Content-Type": mime_type},
    )
    return image_urn


def _upload_linkedin_video(token: str, owner_urn: str, media_url: str) -> str:
    local_path = UPLOADS_DIRECTORY / Path(media_url).name
    if not local_path.is_file():
        raise PublishError("The selected video is no longer available")
    if local_path.suffix.lower() != ".mp4":
        raise PublishError("LinkedIn video publishing supports MP4 files only")
    contents = local_path.read_bytes()
    if len(contents) < 75 * 1024:
        raise PublishError("LinkedIn videos must be at least 75 KB")

    result, _ = _linkedin_request(
        "https://api.linkedin.com/rest/videos?action=initializeUpload",
        token,
        method="POST",
        payload={
            "initializeUploadRequest": {
                "owner": owner_urn,
                "fileSizeBytes": len(contents),
                "uploadCaptions": False,
                "uploadThumbnail": False,
            }
        },
    )
    upload = result.get("value", {})
    video_urn = upload.get("video")
    instructions = upload.get("uploadInstructions", [])
    upload_token = upload.get("uploadToken", "")
    if not video_urn or not instructions:
        raise PublishError("LinkedIn did not provide video upload instructions")

    part_ids = []
    for instruction in instructions:
        first = int(instruction["firstByte"])
        last = min(int(instruction["lastByte"]), len(contents) - 1)
        _, headers = _linkedin_request(
            instruction["uploadUrl"],
            token,
            method="PUT",
            raw_body=contents[first : last + 1],
            headers={"Content-Type": "application/octet-stream"},
        )
        etag = headers.get("ETag") or headers.get("Etag") or headers.get("etag")
        if not etag:
            raise PublishError("LinkedIn did not confirm a video upload part")
        part_ids.append(etag.strip('"'))

    _linkedin_request(
        "https://api.linkedin.com/rest/videos?action=finalizeUpload",
        token,
        method="POST",
        payload={
            "finalizeUploadRequest": {
                "video": video_urn,
                "uploadToken": upload_token,
                "uploadedPartIds": part_ids,
            }
        },
    )
    return video_urn

def publish_linkedin(post: Post, account: SocialAccount) -> str:
    if account.token_expires_at:
        expires_at = account.token_expires_at
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        if expires_at <= datetime.now(timezone.utc):
            raise PublishError("LinkedIn connection has expired; reconnect LinkedIn")

    token = decrypt_token(account.access_token_encrypted)
    owner_urn = f"urn:li:person:{account.external_account_id}"
    media_urls = json.loads(post.media_urls or "[]")
    content = None
    if media_urls:
        extensions = [Path(url).suffix.lower() for url in media_urls]
        video_extensions = {".mp4", ".mov"}
        has_video = any(extension in video_extensions for extension in extensions)
        if has_video:
            if len(media_urls) != 1:
                raise PublishError("A LinkedIn video post can contain only one video")
            video_urn = _upload_linkedin_video(token, owner_urn, media_urls[0])
            content = {"media": {"id": video_urn}}
        else:
            image_urns = [
                _upload_linkedin_image(token, owner_urn, media_url)
                for media_url in media_urls
            ]
            if len(image_urns) == 1:
                content = {"media": {"id": image_urns[0]}}
            else:
                content = {
                    "multiImage": {
                        "images": [{"id": image_urn} for image_urn in image_urns]
                    }
                }

    payload = {
        "author": owner_urn,
        "commentary": post.caption,
        "visibility": "PUBLIC",
        "distribution": {
            "feedDistribution": "MAIN_FEED",
            "targetEntities": [],
            "thirdPartyDistributionChannels": [],
        },
        "lifecycleState": "PUBLISHED",
        "isReshareDisabledByAuthor": False,
    }
    if content:
        payload["content"] = content

    result, headers = _linkedin_request(
        "https://api.linkedin.com/rest/posts",
        token,
        method="POST",
        payload=payload,
    )
    post_id = headers.get("x-restli-id") or headers.get("X-RestLi-Id") or result.get("id")
    if not post_id:
        raise PublishError("LinkedIn accepted the request but returned no post identifier")
    return post_id


def publish_post(db: Session, post: Post) -> Post:
    platforms = set(post.platforms.split(","))
    unsupported = platforms - {"linkedin"}
    if unsupported:
        raise PublishError(
            "Publishing is currently enabled for LinkedIn only; remove Instagram"
        )

    account = (
        db.query(SocialAccount)
        .filter(
            SocialAccount.owner_id == post.owner_id,
            SocialAccount.provider == "linkedin",
        )
        .first()
    )
    if account is None:
        raise PublishError("Connect your LinkedIn account before publishing")

    try:
        external_id = publish_linkedin(post, account)
        post.external_post_ids = json.dumps({"linkedin": external_id})
        post.status = "published"
        post.published_at = datetime.now(timezone.utc)
        post.publish_error = None
    except PublishError as exc:
        post.status = "failed"
        post.publish_error = str(exc)
        db.commit()
        raise
    db.commit()
    db.refresh(post)
    return post


