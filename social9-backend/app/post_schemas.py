from datetime import datetime, timezone

from pydantic import BaseModel, Field, field_validator, model_validator


VALID_PLATFORMS = {"instagram", "linkedin"}


class MediaUpload(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    data: str


class PostCreate(BaseModel):
    caption: str
    platforms: list[str]
    scheduled_for: datetime | None = None
    media: list[MediaUpload] = Field(default_factory=list)

    @field_validator("caption")
    @classmethod
    def validate_caption(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Caption cannot be empty")
        if len(value) > 3000:
            raise ValueError("Caption cannot exceed 3000 characters")
        return value

    @field_validator("platforms")
    @classmethod
    def validate_platforms(cls, value: list[str]) -> list[str]:
        normalized = list(dict.fromkeys(item.lower() for item in value))
        if not normalized or not set(normalized).issubset(VALID_PLATFORMS):
            raise ValueError("Select Instagram, LinkedIn, or both")
        return normalized

    @model_validator(mode="after")
    def validate_schedule(self):
        if self.scheduled_for is not None:
            scheduled = self.scheduled_for
            if scheduled.tzinfo is None:
                scheduled = scheduled.replace(tzinfo=timezone.utc)
            if scheduled <= datetime.now(timezone.utc):
                raise ValueError("Scheduled time must be in the future")
            self.scheduled_for = scheduled
        return self


class PostResponse(BaseModel):
    id: int
    caption: str
    platforms: list[str]
    status: str
    scheduled_for: datetime | None
    media_urls: list[str]
    external_post_ids: dict[str, str]
    publish_error: str | None
    published_at: datetime | None
    created_at: datetime


class PostScheduleUpdate(BaseModel):
    scheduled_for: datetime

    @field_validator("scheduled_for")
    @classmethod
    def validate_scheduled_for(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        if value <= datetime.now(timezone.utc):
            raise ValueError("Scheduled time must be in the future")
        return value


class PostUpdate(BaseModel):
    caption: str
    platforms: list[str]
    scheduled_for: datetime | None = None

    @field_validator("caption")
    @classmethod
    def validate_caption(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Caption cannot be empty")
        if len(value) > 3000:
            raise ValueError("Caption cannot exceed 3000 characters")
        return value

    @field_validator("platforms")
    @classmethod
    def validate_platforms(cls, value: list[str]) -> list[str]:
        normalized = list(dict.fromkeys(item.lower() for item in value))
        if not normalized or not set(normalized).issubset(VALID_PLATFORMS):
            raise ValueError("Select Instagram, LinkedIn, or both")
        return normalized

    @field_validator("scheduled_for")
    @classmethod
    def validate_scheduled_for(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return value
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        if value <= datetime.now(timezone.utc):
            raise ValueError("Scheduled time must be in the future")
        return value
