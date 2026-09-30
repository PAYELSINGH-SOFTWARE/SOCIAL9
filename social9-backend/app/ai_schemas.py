from typing import Literal

from pydantic import BaseModel, Field, field_validator


AI_ACTIONS = {"caption", "improve", "hashtags", "shorten"}


class AIAssistRequest(BaseModel):
    action: Literal["caption", "improve", "hashtags", "shorten"]
    topic: str = Field(min_length=2, max_length=500)
    platform: Literal["instagram", "linkedin", "both"] = "both"

    @field_validator("topic")
    @classmethod
    def normalize_topic(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 2:
            raise ValueError("Add a little more context for the assistant")
        return value


class AIAssistResponse(BaseModel):
    action: str
    content: str
    suggestions: list[str] = Field(default_factory=list)
    simulated: bool
