from datetime import datetime

from pydantic import BaseModel


class FeatureEntitlements(BaseModel):
    growth_projection: bool


class SubscriptionResponse(BaseModel):
    plan: str
    status: str
    is_paid: bool
    mock_mode: bool
    current_period_end: datetime | None = None
    cancel_at_period_end: bool = False
    features: FeatureEntitlements


class FeatureAccessResponse(BaseModel):
    feature: str
    allowed: bool
