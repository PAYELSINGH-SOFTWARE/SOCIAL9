import json
import os
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..models import Post, SocialAccount, User
from .accounts import decrypt_token
from .auth import get_current_user, get_db

router = APIRouter()
LINKEDIN_API_VERSION = os.getenv("LINKEDIN_API_VERSION", "202604")
LINKEDIN_METRICS = {
    "impressions": "IMPRESSION",
    "members_reached": "MEMBERS_REACHED",
    "reactions": "REACTION",
    "comments": "COMMENT",
    "reshares": "RESHARE",
    "post_saves": "POST_SAVE",
    "post_sends": "POST_SEND",
    "link_clicks": "LINK_CLICKS",
}


@router.get("/summary")
def analytics_summary(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    posts = db.query(Post).filter(Post.owner_id == user.id).all()
    status_counts = {"draft": 0, "scheduled": 0, "published": 0, "failed": 0}
    platform_counts = {"instagram": 0, "linkedin": 0}

    for post in posts:
        if post.status in status_counts:
            status_counts[post.status] += 1
        for platform in post.platforms.split(","):
            platform = platform.strip().lower()
            if platform in platform_counts:
                platform_counts[platform] += 1

    attempted = status_counts["published"] + status_counts["failed"]
    success_rate = (
        round((status_counts["published"] / attempted) * 100, 1)
        if attempted
        else 0.0
    )
    connected = [
        account.provider
        for account in db.query(SocialAccount)
        .filter(
            SocialAccount.owner_id == user.id,
            SocialAccount.status == "connected",
        )
        .all()
    ]

    return {
        "total_posts": len(posts),
        "drafts": status_counts["draft"],
        "scheduled": status_counts["scheduled"],
        "published": status_counts["published"],
        "failed": status_counts["failed"],
        "success_rate": success_rate,
        "posts_by_platform": platform_counts,
        "connected_accounts": connected,
    }


def linkedin_metric(access_token: str, query_type: str) -> int:
    query = urlencode(
        {"q": "me", "queryType": query_type, "aggregation": "TOTAL"}
    )
    request = Request(
        f"https://api.linkedin.com/rest/memberCreatorPostAnalytics?{query}",
        headers={
            "Authorization": f"Bearer {access_token}",
            "LinkedIn-Version": LINKEDIN_API_VERSION,
            "X-Restli-Protocol-Version": "2.0.0",
        },
    )
    with urlopen(request, timeout=20) as response:
        payload = json.loads(response.read())
    return sum(int(item.get("count", 0)) for item in payload.get("elements", []))


@router.get("/performance")
def performance_analytics(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    empty_metrics = {key: None for key in LINKEDIN_METRICS}
    account = (
        db.query(SocialAccount)
        .filter(
            SocialAccount.owner_id == user.id,
            SocialAccount.provider == "linkedin",
            SocialAccount.status == "connected",
        )
        .first()
    )
    if account is None:
        return {
            "provider": "linkedin",
            "available": False,
            "reason": "Connect LinkedIn to load post performance metrics.",
            "metrics": empty_metrics,
        }

    if os.getenv("LINKEDIN_ENABLE_ANALYTICS", "false").lower() != "true":
        return {
            "provider": "linkedin",
            "available": False,
            "reason": (
                "LinkedIn analytics requires Community Management approval and "
                "the r_member_postAnalytics permission."
            ),
            "metrics": empty_metrics,
        }

    access_token = decrypt_token(account.access_token_encrypted)
    try:
        metrics = {
            key: linkedin_metric(access_token, query_type)
            for key, query_type in LINKEDIN_METRICS.items()
        }
    except HTTPError as exc:
        if exc.code in (401, 403):
            reason = (
                "LinkedIn has not granted r_member_postAnalytics. Approve the "
                "permission, enable it, and reconnect LinkedIn."
            )
        else:
            reason = f"LinkedIn analytics request failed ({exc.code})."
        return {
            "provider": "linkedin",
            "available": False,
            "reason": reason,
            "metrics": empty_metrics,
        }
    except (URLError, TimeoutError, json.JSONDecodeError):
        return {
            "provider": "linkedin",
            "available": False,
            "reason": "Could not reach LinkedIn analytics. Try again shortly.",
            "metrics": empty_metrics,
        }

    return {
        "provider": "linkedin",
        "available": True,
        "reason": None,
        "metrics": metrics,
    }
