import base64
import binascii
import json
import re
from datetime import datetime
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_
from sqlalchemy.orm import Session

from .auth import get_current_user, get_db
from .models import Post, User
from .media_storage import MediaStorageError, delete_media, store_media
from .post_schemas import MediaUpload, PostCreate, PostResponse, PostScheduleUpdate, PostUpdate
from .publishing import publish_post


router = APIRouter(prefix="/posts", tags=["Posts"])
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".mp4", ".mov"}
MAX_MEDIA_FILES = 10
MAX_MEDIA_BYTES = 10 * 1024 * 1024
VALID_STATUSES = {"draft", "scheduled", "publishing", "published", "failed"}


def _save_media(media: list[MediaUpload]) -> list[str]:
    if len(media) > MAX_MEDIA_FILES:
        raise HTTPException(status_code=400, detail="Select no more than 10 media files")

    urls: list[str] = []
    try:
        for item in media:
            safe_name = Path(item.name).name
            extension = Path(safe_name).suffix.lower()
            if extension not in ALLOWED_EXTENSIONS:
                raise HTTPException(status_code=400, detail=f"Unsupported file type: {extension or safe_name}")
            try:
                encoded = re.sub(r"^data:[^;]+;base64,", "", item.data)
                contents = base64.b64decode(encoded, validate=True)
            except (binascii.Error, ValueError):
                raise HTTPException(status_code=400, detail=f"Invalid file: {safe_name}") from None
            if len(contents) > MAX_MEDIA_BYTES:
                raise HTTPException(status_code=400, detail=f"{safe_name} exceeds the 10 MB limit")
            urls.append(store_media(f"{uuid4().hex}{extension}", contents))
    except Exception as error:
        for media_url in urls:
            try:
                delete_media(media_url)
            except MediaStorageError:
                pass
        if isinstance(error, MediaStorageError):
            raise HTTPException(status_code=503, detail=str(error)) from error
        raise
    return urls


def _delete_unreferenced_media(database: Session, post: Post) -> None:
    media_urls = json.loads(post.media_urls or "[]")
    other_media = {
        value
        for other in database.query(Post).filter(Post.id != post.id).all()
        for value in json.loads(other.media_urls or "[]")
    }
    for media_url in media_urls:
        if media_url not in other_media:
            delete_media(media_url)


def _response(post: Post) -> PostResponse:
    return PostResponse(
        id=post.id,
        caption=post.caption,
        platforms=post.platforms.split(","),
        status=post.status,
        scheduled_for=post.scheduled_for,
        media_urls=json.loads(post.media_urls or "[]"),
        external_post_ids=json.loads(post.external_post_ids or "{}"),
        publish_error=post.publish_error,
        published_at=post.published_at,
        created_at=post.created_at,
    )


@router.post("", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
def create_post(
    data: PostCreate,
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> PostResponse:
    post = Post(
        owner_id=current_user.id,
        caption=data.caption,
        platforms=",".join(data.platforms),
        status="scheduled" if data.scheduled_for else "draft",
        scheduled_for=data.scheduled_for,
        media_urls=json.dumps(_save_media(data.media)),
    )
    database.add(post)
    database.commit()
    database.refresh(post)
    return _response(post)


@router.post("/{post_id}/publish", response_model=PostResponse)
def publish_post_now(
    post_id: int,
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> PostResponse:
    post = database.query(Post).filter(Post.id == post_id, Post.owner_id == current_user.id).first()
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")
    if post.status == "publishing":
        raise HTTPException(status_code=409, detail="This post is already being published")
    return _response(publish_post(database, post))


@router.get("", response_model=list[PostResponse])
def list_posts(
    post_status: str | None = Query(default=None, alias="status"),
    platform: str | None = Query(default=None),
    search: str | None = Query(default=None, max_length=120),
    date_from: datetime | None = Query(default=None),
    date_to: datetime | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> list[PostResponse]:
    if post_status and post_status not in VALID_STATUSES:
        raise HTTPException(status_code=400, detail="Invalid post status")
    if platform and platform not in {"instagram", "linkedin"}:
        raise HTTPException(status_code=400, detail="Invalid platform")
    query = database.query(Post).filter(Post.owner_id == current_user.id)
    if post_status:
        query = query.filter(Post.status == post_status)
    if platform:
        query = query.filter(
            or_(
                Post.platforms == platform,
                Post.platforms.like(f"{platform},%"),
                Post.platforms.like(f"%,{platform}"),
                Post.platforms.like(f"%,{platform},%"),
            )
        )
    if search and search.strip():
        query = query.filter(Post.caption.ilike(f"%{search.strip()}%"))
    if date_from:
        query = query.filter(Post.scheduled_for >= date_from)
    if date_to:
        query = query.filter(Post.scheduled_for < date_to)
    if date_from and date_to and date_from >= date_to:
        raise HTTPException(status_code=400, detail="date_from must be before date_to")
    return [
        _response(post)
        for post in query.order_by(Post.created_at.desc()).offset(offset).limit(limit).all()
    ]


@router.patch("/{post_id}", response_model=PostResponse)
def update_post(
    post_id: int,
    data: PostUpdate,
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> PostResponse:
    post = database.query(Post).filter(Post.id == post_id, Post.owner_id == current_user.id).first()
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")
    if post.status in {"published", "publishing"}:
        raise HTTPException(status_code=409, detail="Published posts cannot be edited")
    post.caption = data.caption
    post.platforms = ",".join(data.platforms)
    post.scheduled_for = data.scheduled_for
    post.status = "scheduled" if data.scheduled_for else "draft"
    post.publish_error = None
    database.commit()
    database.refresh(post)
    return _response(post)


@router.post("/{post_id}/duplicate", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
def duplicate_post(
    post_id: int,
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> PostResponse:
    source = database.query(Post).filter(Post.id == post_id, Post.owner_id == current_user.id).first()
    if source is None:
        raise HTTPException(status_code=404, detail="Post not found")
    duplicate = Post(
        owner_id=current_user.id,
        caption=source.caption,
        platforms=source.platforms,
        status="draft",
        scheduled_for=None,
        media_urls=source.media_urls,
    )
    database.add(duplicate)
    database.commit()
    database.refresh(duplicate)
    return _response(duplicate)


@router.patch("/{post_id}/schedule", response_model=PostResponse)
def reschedule_post(
    post_id: int,
    data: PostScheduleUpdate,
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> PostResponse:
    post = database.query(Post).filter(Post.id == post_id, Post.owner_id == current_user.id).first()
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")
    if post.status == "published":
        raise HTTPException(status_code=409, detail="Published posts cannot be rescheduled")
    post.scheduled_for = data.scheduled_for
    post.status = "scheduled"
    database.commit()
    database.refresh(post)
    return _response(post)


@router.patch("/{post_id}/draft", response_model=PostResponse)
def move_to_draft(
    post_id: int,
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> PostResponse:
    post = database.query(Post).filter(Post.id == post_id, Post.owner_id == current_user.id).first()
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")
    if post.status == "published":
        raise HTTPException(status_code=409, detail="Published posts cannot become drafts")
    post.scheduled_for = None
    post.status = "draft"
    database.commit()
    database.refresh(post)
    return _response(post)


@router.delete("/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_post(
    post_id: int,
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> None:
    post = database.query(Post).filter(Post.id == post_id, Post.owner_id == current_user.id).first()
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")
    try:
        _delete_unreferenced_media(database, post)
    except MediaStorageError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    database.delete(post)
    database.commit()
