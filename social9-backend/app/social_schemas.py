from datetime import datetime

from pydantic import BaseModel, ConfigDict


class SocialAccountResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    provider: str
    provider_account_id: str
    account_name: str
    username: str | None
    status: str
    expires_at: datetime | None
    created_at: datetime


class ConnectResponse(BaseModel):
    provider: str
    authorization_url: str


class ProviderStatusResponse(BaseModel):
    provider: str
    mode: str
    configured: bool
