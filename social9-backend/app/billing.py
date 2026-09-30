import os
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from .auth import get_current_user, get_db
from .billing_schemas import FeatureAccessResponse, SubscriptionResponse
from .models import Subscription, User


router = APIRouter(prefix="/billing", tags=["Billing"])
ACTIVE_SUBSCRIPTION_STATUSES = {"active", "trialing"}


def billing_mock_mode() -> bool:
    return os.getenv("BILLING_MOCK_MODE", "false").lower() == "true"


def get_subscription(database: Session, user_id: int) -> Subscription | None:
    return database.query(Subscription).filter(Subscription.user_id == user_id).first()


def growth_projection_enabled(subscription: Subscription | None) -> bool:
    return bool(
        subscription
        and subscription.plan == "pro"
        and subscription.status in ACTIVE_SUBSCRIPTION_STATUSES
    )


def subscription_response(subscription: Subscription | None) -> SubscriptionResponse:
    paid = growth_projection_enabled(subscription)
    return SubscriptionResponse(
        plan=subscription.plan if subscription else "free",
        status=subscription.status if subscription else "inactive",
        is_paid=paid,
        mock_mode=billing_mock_mode(),
        current_period_end=subscription.current_period_end if subscription else None,
        cancel_at_period_end=subscription.cancel_at_period_end if subscription else False,
        features={"growth_projection": paid},
    )


def require_growth_projection_access(
    user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> User:
    if not growth_projection_enabled(get_subscription(database, user.id)):
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail="Growth forecasting requires an active paid subscription",
        )
    return user


@router.get("/subscription", response_model=SubscriptionResponse)
def read_subscription(
    user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> SubscriptionResponse:
    return subscription_response(get_subscription(database, user.id))


@router.get(
    "/features/growth-projection/access", response_model=FeatureAccessResponse
)
def read_growth_projection_access(
    _: User = Depends(require_growth_projection_access),
) -> FeatureAccessResponse:
    return FeatureAccessResponse(feature="growth_projection", allowed=True)


@router.post("/mock/subscribe", response_model=SubscriptionResponse)
def mock_subscribe(
    user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> SubscriptionResponse:
    if not billing_mock_mode():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")

    subscription = get_subscription(database, user.id)
    if subscription is None:
        subscription = Subscription(user_id=user.id)
        database.add(subscription)

    subscription.provider = "mock"
    subscription.provider_subscription_id = f"mock-subscription-{user.id}"
    subscription.plan = "pro"
    subscription.status = "active"
    subscription.current_period_end = datetime.now(timezone.utc) + timedelta(days=30)
    subscription.cancel_at_period_end = False
    database.commit()
    database.refresh(subscription)
    return subscription_response(subscription)


@router.post("/mock/cancel", response_model=SubscriptionResponse)
def mock_cancel(
    user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> SubscriptionResponse:
    if not billing_mock_mode():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")

    subscription = get_subscription(database, user.id)
    if subscription is not None:
        subscription.status = "canceled"
        subscription.current_period_end = None
        subscription.cancel_at_period_end = False
        database.commit()
        database.refresh(subscription)
    return subscription_response(subscription)
