import json
from collections import Counter
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from .auth import get_current_user, get_db
from .instagram_insights import instagram_metrics
from .models import Post, SocialAccount, User


router = APIRouter(prefix="/analytics", tags=["Analytics"])
SUPPORTED_RANGES = {7, 30, 90}
RECYCLE_AFTER_DAYS = 14


def _aware(value: datetime | None) -> datetime | None:
    if value is None or value.tzinfo is not None:
        return value
    return value.replace(tzinfo=timezone.utc)


def _week_start(value: datetime) -> datetime:
    return (value - timedelta(days=value.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    )


def _publishing_consistency(posts: list[Post], now: datetime) -> dict:
    current_week = _week_start(now)
    next_week = current_week + timedelta(days=7)
    published = [
        _aware(post.published_at) or _aware(post.created_at)
        for post in posts
        if post.status == "published"
    ]
    published_dates = [value for value in published if value is not None]
    active_weeks = {_week_start(value) for value in published_dates}
    published_this_week = sum(current_week <= value < next_week for value in published_dates)
    scheduled_this_week = sum(
        post.status == "scheduled"
        and (_aware(post.scheduled_for) or next_week) >= now
        and (_aware(post.scheduled_for) or next_week) < next_week
        for post in posts
    )

    cursor = current_week if current_week in active_weeks else current_week - timedelta(days=7)
    streak = 0
    while cursor in active_weeks:
        streak += 1
        cursor -= timedelta(days=7)

    at_risk = current_week not in active_weeks and streak > 0 and scheduled_this_week == 0
    if published_this_week:
        state = "active"
        message = "This week's publish is complete. Keep the rhythm visible on your calendar."
    elif scheduled_this_week:
        state = "protected"
        message = "Your next scheduled post protects the current weekly rhythm."
    elif at_risk:
        state = "at_risk"
        message = "Publish or schedule once before Monday to keep the streak alive."
    else:
        state = "start"
        message = "Publish once this week to begin a consistent posting streak."

    return {
        "current_streak": streak,
        "longest_streak": _longest_weekly_streak(active_weeks),
        "published_this_week": published_this_week,
        "scheduled_this_week": scheduled_this_week,
        "days_remaining": max(0, (next_week.date() - now.date()).days),
        "state": state,
        "at_risk": at_risk,
        "message": message,
        "week_ends_at": next_week.isoformat(),
    }


def _longest_weekly_streak(active_weeks: set[datetime]) -> int:
    longest = 0
    for week in active_weeks:
        if week - timedelta(days=7) in active_weeks:
            continue
        length = 1
        cursor = week + timedelta(days=7)
        while cursor in active_weeks:
            length += 1
            cursor += timedelta(days=7)
        longest = max(longest, length)
    return longest


def _recycling_candidates(
    posts: list[Post], instagram: dict | None, now: datetime
) -> dict:
    engagement_by_media = {
        str(item.get("id")): int(item.get("interactions") or 0)
        for item in (instagram or {}).get("top_media", [])
        if isinstance(item, dict) and item.get("id")
    }
    candidates = []
    waiting_days: list[int] = []
    for post in posts:
        published_at = _aware(post.published_at)
        if post.status != "published" or published_at is None:
            continue
        age_days = max(0, (now.date() - published_at.date()).days)
        if age_days < RECYCLE_AFTER_DAYS:
            waiting_days.append(RECYCLE_AFTER_DAYS - age_days)
            continue
        try:
            external_ids = json.loads(post.external_post_ids or "{}")
            media_urls = json.loads(post.media_urls or "[]")
        except (TypeError, ValueError):
            continue
        live_ids = {
            provider: str(external_id)
            for provider, external_id in external_ids.items()
            if external_id and not str(external_id).startswith("preview:")
        }
        if not live_ids:
            continue
        interactions = max(
            (engagement_by_media.get(external_id, 0) for external_id in live_ids.values()),
            default=0,
        )
        reason = (
            f"Earned {interactions} Instagram interactions"
            if interactions
            else f"Last published {age_days} days ago"
        )
        candidates.append(
            {
                "post_id": post.id,
                "caption": post.caption,
                "platforms": post.platforms.split(","),
                "published_at": published_at.isoformat(),
                "age_days": age_days,
                "interactions": interactions,
                "reason": reason,
                "media_url": media_urls[0] if media_urls else None,
            }
        )
    candidates.sort(
        key=lambda item: (item["interactions"] > 0, item["interactions"], item["age_days"]),
        reverse=True,
    )
    return {
        "eligible_count": len(candidates),
        "next_ready_in_days": min(waiting_days) if waiting_days and not candidates else 0,
        "candidates": candidates[:3],
    }


def _suggestions(counts: Counter, connected: set[str], recent_posts: int) -> list[dict[str, str]]:
    suggestions: list[dict[str, str]] = []
    if not connected:
        suggestions.append({"title": "Connect a publishing channel", "body": "Connect LinkedIn or Instagram so drafts can move into a live publishing workflow.", "action": "Connect accounts", "href": "/accounts", "tone": "priority"})
    if counts["failed"]:
        suggestions.append({"title": "Clear publishing failures", "body": f"{counts['failed']} post{'s' if counts['failed'] != 1 else ''} need attention. Review the error and reconnect the affected account if needed.", "action": "Review posts", "href": "/create-post", "tone": "warning"})
    if counts["draft"] > counts["scheduled"]:
        suggestions.append({"title": "Turn drafts into a steady cadence", "body": "You have more drafts than scheduled posts. Spacing a few across the week can keep your publishing rhythm consistent.", "action": "Open calendar", "href": "/calendar", "tone": "growth"})
    if recent_posts == 0:
        suggestions.append({"title": "Create momentum this week", "body": "No content activity is recorded in this range. Start with one useful update and schedule the next while the idea is fresh.", "action": "Create a post", "href": "/create-post", "tone": "growth"})
    if len(connected) == 1:
        missing = "Instagram" if "linkedin" in connected else "LinkedIn"
        suggestions.append({"title": f"Add {missing} to your channel mix", "body": "A second connected channel lets you reuse strong ideas for a different audience without rebuilding the workflow.", "action": "Add channel", "href": "/accounts", "tone": "insight"})
    if counts["published"] and not counts["failed"]:
        suggestions.append({"title": "Your delivery flow is healthy", "body": "Every recorded publish attempt is currently successful. Keep reviewing your calendar before adding more volume.", "action": "View calendar", "href": "/calendar", "tone": "success"})
    return suggestions[:4]


@router.get("/summary")
def analytics_summary(
    days: int = Query(default=30),
    current_user: User = Depends(get_current_user),
    database: Session = Depends(get_db),
) -> dict:
    if days not in SUPPORTED_RANGES:
        raise HTTPException(status_code=400, detail="Analytics range must be 7, 30, or 90 days")

    now = datetime.now(timezone.utc)
    start = now - timedelta(days=days - 1)
    posts = database.query(Post).filter(Post.owner_id == current_user.id).all()
    accounts = database.query(SocialAccount).filter(
        SocialAccount.user_id == current_user.id,
        SocialAccount.status == "connected",
    ).all()
    connected = {account.provider for account in accounts}
    instagram, provider_reason = instagram_metrics(database, accounts, days)
    counts = Counter(post.status for post in posts)
    attempts = counts["published"] + counts["failed"]
    period_posts = [post for post in posts if (_aware(post.created_at) or now) >= start]
    external_ids = {post.id: json.loads(post.external_post_ids or "{}") for post in posts}
    preview_published = sum(post.status == "published" and any(str(value).startswith("preview:") for value in external_ids[post.id].values()) for post in posts)
    provider_published = counts["published"] - preview_published
    point_count = 7 if days <= 30 else 12
    interval = max(1, days // point_count)
    trend = []
    for index in range(point_count):
        bucket_start = (now - timedelta(days=(point_count - index - 1) * interval)).date()
        bucket_end = bucket_start + timedelta(days=interval)
        bucket_posts = [post for post in posts if bucket_start <= (_aware(post.created_at) or now).date() < bucket_end]
        trend.append({"date": bucket_start.isoformat(), "created": len(bucket_posts), "published": sum(post.status == "published" for post in bucket_posts), "scheduled": sum(post.status == "scheduled" for post in bucket_posts), "failed": sum(post.status == "failed" for post in bucket_posts)})

    channel_data = []
    for provider in ("instagram", "linkedin"):
        provider_posts = [post for post in posts if provider in post.platforms.split(",")]
        channel_data.append({"provider": provider, "connected": provider in connected, "post_count": len(provider_posts), "published": sum(post.status == "published" for post in provider_posts), "scheduled": sum(post.status == "scheduled" for post in provider_posts), "failed": sum(post.status == "failed" for post in provider_posts)})

    upcoming = sorted((post for post in posts if post.status == "scheduled" and post.scheduled_for), key=lambda post: _aware(post.scheduled_for) or now)[:5]
    recent = sorted(posts, key=lambda post: _aware(post.created_at) or now, reverse=True)[:6]

    return {
        "simulated": False,
        "provider_metrics_available": instagram is not None,
        "provider_metrics_reason": provider_reason,
        "provider_metrics": {"instagram": instagram},
        "range_days": days,
        "overview": {
            "total_posts": len(posts),
            "posts_in_range": len(period_posts),
            "drafts": counts["draft"],
            "scheduled": counts["scheduled"],
            "publishing": counts["publishing"],
            "published": counts["published"],
            "provider_published": provider_published,
            "preview_published": preview_published,
            "failed": counts["failed"],
            "connected_accounts": len(accounts),
            "publish_success_rate": round(counts["published"] / attempts * 100, 1) if attempts else 0,
        },
        "trend": trend,
        "channels": channel_data,
        "consistency": _publishing_consistency(posts, now),
        "recycling": _recycling_candidates(posts, instagram, now),
        "suggestions": _suggestions(counts, connected, len(period_posts)),
        "upcoming_posts": [{"id": post.id, "caption": post.caption, "platforms": post.platforms.split(","), "scheduled_for": _aware(post.scheduled_for).isoformat()} for post in upcoming],
        "recent_posts": [{"id": post.id, "caption": post.caption, "platforms": post.platforms.split(","), "status": post.status, "created_at": _aware(post.created_at).isoformat(), "published_at": _aware(post.published_at).isoformat() if post.published_at else None, "publish_error": post.publish_error, "delivery_ids": len(external_ids[post.id]), "delivery_mode": "preview" if any(str(value).startswith("preview:") for value in external_ids[post.id].values()) else "provider" if external_ids[post.id] else "none"} for post in recent],
    }
