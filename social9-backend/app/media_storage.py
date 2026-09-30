import io
import mimetypes
import os
from pathlib import Path
from urllib.parse import unquote, urlparse

import httpx


UPLOADS_DIRECTORY = Path(__file__).resolve().parent.parent / "uploads"
MAX_MEDIA_BYTES = 10 * 1024 * 1024


class MediaStorageError(RuntimeError):
    """A safe media-storage error suitable for returning to a user."""


def storage_backend() -> str:
    return os.getenv("MEDIA_STORAGE_BACKEND", "local").strip().lower()


def _s3_settings() -> tuple[str, str, str]:
    bucket = os.getenv("S3_BUCKET", "").strip()
    public_base_url = os.getenv("S3_PUBLIC_BASE_URL", "").strip().rstrip("/")
    prefix = os.getenv("S3_KEY_PREFIX", "social9").strip().strip("/")
    if not bucket or not public_base_url:
        raise MediaStorageError(
            "Persistent media storage is not fully configured"
        )
    return bucket, public_base_url, prefix


def _s3_client():
    try:
        import boto3
    except ImportError as error:
        raise MediaStorageError("Persistent media storage is unavailable") from error

    options: dict[str, str] = {}
    endpoint_url = os.getenv("S3_ENDPOINT_URL", "").strip()
    region = os.getenv("AWS_REGION", "").strip()
    if endpoint_url:
        options["endpoint_url"] = endpoint_url
    if region:
        options["region_name"] = region
    return boto3.client("s3", **options)


def store_media(filename: str, contents: bytes) -> str:
    """Persist media and return the URL stored on the post record."""
    if storage_backend() == "local":
        UPLOADS_DIRECTORY.mkdir(exist_ok=True)
        (UPLOADS_DIRECTORY / filename).write_bytes(contents)
        return f"/uploads/{filename}"

    if storage_backend() != "s3":
        raise MediaStorageError("Unsupported media storage backend")

    bucket, public_base_url, prefix = _s3_settings()
    key = f"{prefix}/{filename}" if prefix else filename
    content_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"
    try:
        _s3_client().upload_fileobj(
            io.BytesIO(contents),
            bucket,
            key,
            ExtraArgs={
                "ContentType": content_type,
                "CacheControl": "public, max-age=31536000, immutable",
            },
        )
    except Exception as error:
        raise MediaStorageError("The uploaded media could not be stored") from error
    return f"{public_base_url}/{key}"


def media_extension(media_url: str) -> str:
    return Path(urlparse(media_url).path).suffix.lower()


def public_media_url(media_url: str) -> str:
    if media_url.startswith(("https://", "http://")):
        return media_url
    backend_url = os.getenv(
        "BACKEND_PUBLIC_URL",
        os.getenv("RENDER_EXTERNAL_URL", "http://127.0.0.1:8000"),
    ).rstrip("/")
    return f"{backend_url}{media_url}"


def read_media_bytes(media_url: str, client: httpx.Client) -> tuple[bytes, str]:
    """Read local or remote media for providers that require binary upload."""
    if media_url.startswith("/uploads/"):
        path = (UPLOADS_DIRECTORY / Path(media_url).name).resolve()
        uploads = UPLOADS_DIRECTORY.resolve()
        if uploads not in path.parents or not path.is_file():
            raise MediaStorageError("The uploaded media file is no longer available")
        contents = path.read_bytes()
        return contents, mimetypes.guess_type(path.name)[0] or "application/octet-stream"

    response = client.get(media_url, headers={"Accept": "*/*"})
    if not response.is_success:
        raise MediaStorageError("The stored media file could not be retrieved")
    contents = response.content
    if len(contents) > MAX_MEDIA_BYTES:
        raise MediaStorageError("The stored media file exceeds the 10 MB limit")
    content_type = response.headers.get("content-type", "").split(";", 1)[0]
    return contents, content_type or mimetypes.guess_type(media_url)[0] or "application/octet-stream"


def delete_media(media_url: str) -> None:
    if media_url.startswith("/uploads/"):
        path = (UPLOADS_DIRECTORY / Path(media_url).name).resolve()
        if UPLOADS_DIRECTORY.resolve() in path.parents:
            path.unlink(missing_ok=True)
        return

    if storage_backend() != "s3":
        return
    bucket, public_base_url, _ = _s3_settings()
    prefix = f"{public_base_url}/"
    if not media_url.startswith(prefix):
        return
    key = unquote(media_url.removeprefix(prefix))
    try:
        _s3_client().delete_object(Bucket=bucket, Key=key)
    except Exception as error:
        raise MediaStorageError("The stored media file could not be deleted") from error
