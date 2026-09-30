from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from .auth import get_current_user, get_db
from .models import Post, SocialAccount, User


router = APIRouter(prefix="/workspace", tags=["Workspace"])


def _aware(value: datetime | None) -> datetime | None:
    if value is None or value.tzinfo is not None:
        return value
    return value.replace(tzinfo=timezone.utc)


@router.get("/actions")
def workspace_actions(
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> dict:
    now = datetime.now(timezone.utc)
    posts = database.query(Post).filter(Post.owner_id == current_user.id).all()
    accounts = database.query(SocialAccount).filter(
        SocialAccount.user_id == current_user.id
    ).all()

    failed = sorted(
        (post for post in posts if post.status == "failed"),
        key=lambda post: _aware(post.updated_at) or now,
        reverse=True,
    )
    upcoming = sorted(
        (
            post
            for post in posts
            if post.status == "scheduled"
            and post.scheduled_for
            and now <= (_aware(post.scheduled_for) or now) <= now + timedelta(days=7)
        ),
        key=lambda post: _aware(post.scheduled_for) or now,
    )
    expiring = [
        account
        for account in accounts
        if account.status == "connected"
        and account.expires_at
        and (_aware(account.expires_at) or now) <= now + timedelta(days=7)
    ]
    connected = {account.provider for account in accounts if account.status == "connected"}

    actions: list[dict] = []
    if failed:
        actions.append(
            {
                "id": "failed-posts",
                "priority": "urgent",
                "category": "Publishing",
                "title": f"{len(failed)} post{'s' if len(failed) != 1 else ''} need attention",
                "description": failed[0].publish_error or "A provider rejected the most recent publishing attempt.",
                "action_label": "Review failed posts",
                "href": "/content?status=failed",
                "count": len(failed),
            }
        )
    for account in expiring:
        actions.append(
            {
                "id": f"expiring-{account.id}",
                "priority": "warning",
                "category": "Connection",
                "title": f"Reconnect {account.account_name} soon",
                "description": f"The saved {account.provider.title()} authorization expires within seven days.",
                "action_label": "Review account",
                "href": "/accounts",
                "count": 1,
            }
        )
    for provider in ("instagram", "linkedin"):
        if provider not in connected:
            actions.append(
                {
                    "id": f"missing-{provider}",
                    "priority": "recommended",
                    "category": "Connection",
                    "title": f"Connect {provider.title()}",
                    "description": f"Add {provider.title()} to publish and schedule content from the same workspace.",
                    "action_label": "Connect channel",
                    "href": "/accounts",
                    "count": 1,
                }
            )
    if upcoming:
        next_post = upcoming[0]
        actions.append(
            {
                "id": "upcoming-week",
                "priority": "info",
                "category": "Schedule",
                "title": f"{len(upcoming)} post{'s' if len(upcoming) != 1 else ''} scheduled this week",
                "description": f"Next up: {next_post.caption[:100]}",
                "action_label": "Review calendar",
                "href": "/calendar",
                "count": len(upcoming),
            }
        )
    if not actions:
        actions.append(
            {
                "id": "workspace-clear",
                "priority": "success",
                "category": "Workspace",
                "title": "Everything is on track",
                "description": "There are no failed posts, expiring connections, or urgent schedule checks right now.",
                "action_label": "Create a post",
                "href": "/create-post",
                "count": 0,
            }
        )

    return {
        "generated_at": now.isoformat(),
        "summary": {
            "urgent": sum(item["priority"] == "urgent" for item in actions),
            "recommended": sum(item["priority"] in {"warning", "recommended"} for item in actions),
            "scheduled_this_week": len(upcoming),
        },
        "actions": actions,
    }
