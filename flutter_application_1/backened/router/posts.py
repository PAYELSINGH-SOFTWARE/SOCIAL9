import base64
import binascii
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy.orm import Session

from ..models import Post, User
from ..publisher import PublishError, publish_post
from .auth import get_current_user, get_db

router = APIRouter()
VALID_PLATFORMS = {"instagram", "linkedin"}
VALID_STATUSES = {"draft", "scheduled", "published", "failed"}
UPLOADS_DIRECTORY = Path(__file__).resolve().parent.parent / "uploads"
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".mp4", ".mov"}
MAX_MEDIA_FILES = 10
MAX_MEDIA_BYTES = 10 * 1024 * 1024


class MediaUpload(BaseModel):
    name: str
    data: str


class PostCreate(BaseModel):
    caption: str
    platforms: list[str]
    scheduled_for: datetime | None = None
    media: list[MediaUpload] = Field(default_factory=list)
    publish_now: bool = False

    @field_validator("caption")
    @classmethod
    def validate_caption(cls, value: str):
        value = value.strip()
        if not value:
            raise ValueError("Caption cannot be empty")
        if len(value) > 3000:
            raise ValueError("Caption cannot exceed 3000 characters")
        return value

    @field_validator("platforms")
    @classmethod
    def validate_platforms(cls, value: list[str]):
        normalized = list(dict.fromkeys(item.lower() for item in value))
        if not normalized or not set(normalized).issubset(VALID_PLATFORMS):
            raise ValueError("Select Instagram, LinkedIn, or both")
        return normalized

    @model_validator(mode="after")
    def validate_schedule(self):
        if self.publish_now and self.scheduled_for:
            raise ValueError("Choose either Publish Now or Schedule")
        if self.scheduled_for:
            scheduled = self.scheduled_for
            if scheduled.tzinfo is None:
                scheduled = scheduled.replace(tzinfo=timezone.utc)
            if scheduled <= datetime.now(timezone.utc):
                raise ValueError("Scheduled time must be in the future")
            self.scheduled_for = scheduled
        return self


def save_media(media: list[MediaUpload]) -> list[str]:
    if len(media) > MAX_MEDIA_FILES:
        raise HTTPException(status_code=400, detail="Select no more than 10 media files")

    urls = []
    UPLOADS_DIRECTORY.mkdir(exist_ok=True)
    for item in media:
        safe_name = Path(item.name).name
        extension = Path(safe_name).suffix.lower()
        if extension not in ALLOWED_EXTENSIONS:
            raise HTTPException(
                status_code=400,
                detail=f"Unsupported file type: {extension or safe_name}",
            )
        try:
            encoded = re.sub(r"^data:[^;]+;base64,", "", item.data)
            contents = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError):
            raise HTTPException(status_code=400, detail=f"Invalid file: {safe_name}")
        if len(contents) > MAX_MEDIA_BYTES:
            raise HTTPException(
                status_code=400,
                detail=f"{safe_name} exceeds the 10 MB limit",
            )
        filename = f"{uuid4().hex}{extension}"
        (UPLOADS_DIRECTORY / filename).write_bytes(contents)
        urls.append(f"/uploads/{filename}")
    return urls


def serialize(post: Post):
    return {
        "id": post.id,
        "caption": post.caption,
        "media_urls": json.loads(post.media_urls or "[]"),
        "external_post_ids": json.loads(post.external_post_ids or "{}"),
        "publish_error": post.publish_error,
        "published_at": post.published_at,
        "platforms": post.platforms.split(","),
        "status": post.status,
        "scheduled_for": post.scheduled_for,
        "created_at": post.created_at,
    }


@router.post("", status_code=201)
def create_post(
    data: PostCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    media_urls = save_media(data.media)
    post = Post(
        caption=data.caption,
        media_urls=json.dumps(media_urls),
        platforms=",".join(data.platforms),
        status="scheduled" if data.scheduled_for else "draft",
        scheduled_for=data.scheduled_for,
        created_at=datetime.now(timezone.utc),
        owner_id=user.id,
    )
    db.add(post)
    db.commit()
    db.refresh(post)
    if data.publish_now:
        try:
            publish_post(db, post)
        except PublishError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
    return serialize(post)


@router.post("/{post_id}/publish")
def publish_saved_post(
    post_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    post = (
        db.query(Post)
        .filter(Post.id == post_id, Post.owner_id == user.id)
        .first()
    )
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")
    if post.status == "published":
        raise HTTPException(status_code=409, detail="Post is already published")
    try:
        publish_post(db, post)
    except PublishError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return serialize(post)


@router.get("")
def list_posts(
    status: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if status and status not in VALID_STATUSES:
        raise HTTPException(status_code=400, detail="Invalid post status")
    query = db.query(Post).filter(Post.owner_id == user.id)
    if status:
        query = query.filter(Post.status == status)
    return [serialize(post) for post in query.order_by(Post.created_at.desc()).all()]


@router.delete("/{post_id}", status_code=204)
def delete_post(
    post_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    post = (
        db.query(Post)
        .filter(Post.id == post_id, Post.owner_id == user.id)
        .first()
    )
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")
    db.delete(post)
    db.commit()


