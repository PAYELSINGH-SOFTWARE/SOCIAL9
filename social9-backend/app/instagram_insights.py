from collections import defaultdict
from datetime import datetime, timedelta, timezone
import os

import httpx
from sqlalchemy.orm import Session

from .models import SocialAccount
from .publishing import INSTAGRAM_GRAPH_URL, _instagram_access_token


class InstagramInsightsError(RuntimeError):
    """A safe Instagram insights failure suitable for the dashboard."""


ACCOUNT_METRIC_GROUPS = (
    ("reach", "profile_views"),
    ("views",),
    ("follower_count",),
    ("total_interactions", "likes", "comments", "shares", "saves"),
)
MEDIA_FIELDS = (
    "id,caption,media_type,media_product_type,permalink,timestamp,"
    "like_count,comments_count,thumbnail_url,media_url"
)
MAX_MEDIA_PAGES = 10


def _response_json(response: httpx.Response) -> dict:
    if not response.is_success:
        detail = ""
        try:
            payload = response.json()
            error = payload.get("error") if isinstance(payload, dict) else None
            if isinstance(error, dict):
                detail = str(error.get("error_user_msg") or error.get("message") or "")
        except ValueError:
            pass
        suffix = f": {detail[:220]}" if detail else ""
        raise InstagramInsightsError(
            f"Instagram insights are unavailable ({response.status_code}){suffix}"
        )
    try:
        payload = response.json()
    except ValueError as error:
        raise InstagramInsightsError("Instagram returned an invalid insights response") from error
    if not isinstance(payload, dict):
        raise InstagramInsightsError("Instagram returned an invalid insights response")
    return payload


def _integer(value: object) -> int:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return 0


def _merge_daily_metrics(
    daily: dict[str, dict[str, int]], payload: dict
) -> set[str]:
    loaded: set[str] = set()
    for metric in payload.get("data", []):
        if not isinstance(metric, dict):
            continue
        name = str(metric.get("name") or "")
        if not name:
            continue
        loaded.add(name)
        values = metric.get("values", [])
        if not isinstance(values, list):
            continue
        for point in values:
            if not isinstance(point, dict) or "end_time" not in point:
                continue
            date = str(point["end_time"])[:10]
            daily[date][name] = _integer(point.get("value", 0))
    return loaded


def _daily_insights(payload: dict) -> list[dict[str, int | str]]:
    """Normalize a Meta time-series response for unit tests and callers."""
    daily: dict[str, dict[str, int]] = defaultdict(dict)
    _merge_daily_metrics(daily, payload)
    return _normalized_daily(daily)


def _normalized_daily(
    daily: dict[str, dict[str, int]],
) -> list[dict[str, int | str]]:
    return [
        {
            "date": date,
            "reach": values.get("reach", 0),
            # Meta replaced legacy impressions with views in current API versions.
            "impressions": values.get("views", 0),
            "profile_views": values.get("profile_views", 0),
            "followers_gained": values.get("follower_count", 0),
            "interactions": values.get("total_interactions", 0),
            "shares": values.get("shares", 0),
            "saves": values.get("saves", 0),
        }
        for date, values in sorted(daily.items())
    ]


def _account_insight_series(
    base_url: str,
    access_token: str,
    since: datetime,
    until: datetime,
    client: httpx.Client,
) -> tuple[list[dict[str, int | str]], list[str]]:
    daily: dict[str, dict[str, int]] = defaultdict(dict)
    unavailable: list[str] = []
    loaded_any = False

    # Metrics have different availability rules. Isolated groups allow reach
    # to remain visible when a newer or account-specific metric is unavailable.
    for metrics in ACCOUNT_METRIC_GROUPS:
        try:
            payload = _response_json(
                client.get(
                    f"{base_url}/insights",
                    params={
                        "metric": ",".join(metrics),
                        "period": "day",
                        "since": int(since.timestamp()),
                        "until": int(until.timestamp()),
                        "access_token": access_token,
                    },
                )
            )
        except InstagramInsightsError:
            unavailable.extend(metrics)
            continue
        loaded = _merge_daily_metrics(daily, payload)
        loaded_any = loaded_any or bool(loaded)
        unavailable.extend(metric for metric in metrics if metric not in loaded)

    if not loaded_any:
        raise InstagramInsightsError(
            "Instagram did not return account insights. Reconnect the account and grant insights access."
        )
    return _normalized_daily(daily), sorted(set(unavailable))


def _parse_media_item(item: dict, since: datetime) -> tuple[dict | None, datetime | None]:
    timestamp = str(item.get("timestamp") or "")
    try:
        published_at = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    except ValueError:
        return None, None
    if published_at.tzinfo is None:
        published_at = published_at.replace(tzinfo=timezone.utc)
    if published_at < since:
        return None, published_at

    likes = _integer(item.get("like_count"))
    comments = _integer(item.get("comments_count"))
    media_type = str(
        item.get("media_product_type") or item.get("media_type") or "POST"
    ).upper()
    return (
        {
            "id": str(item.get("id") or ""),
            "caption": str(item.get("caption") or ""),
            "media_type": media_type,
            "permalink": str(item.get("permalink") or ""),
            "thumbnail_url": str(
                item.get("thumbnail_url") or item.get("media_url") or ""
            ),
            "published_at": published_at.isoformat(),
            "likes": likes,
            "comments": comments,
            "interactions": likes + comments,
        },
        published_at,
    )


def _account_media(
    base_url: str,
    access_token: str,
    since: datetime,
    client: httpx.Client,
) -> list[dict]:
    media: list[dict] = []
    after: str | None = None

    for _ in range(MAX_MEDIA_PAGES):
        params: dict[str, str | int] = {
            "fields": MEDIA_FIELDS,
            "limit": 50,
            "access_token": access_token,
        }
        if after:
            params["after"] = after
        payload = _response_json(client.get(f"{base_url}/media", params=params))
        page = payload.get("data", [])
        if not isinstance(page, list) or not page:
            break

        page_is_older = True
        for item in page:
            if not isinstance(item, dict):
                continue
            parsed, published_at = _parse_media_item(item, since)
            if parsed:
                media.append(parsed)
            if published_at is not None and published_at >= since:
                page_is_older = False

        if page_is_older:
            break
        paging = payload.get("paging")
        cursors = paging.get("cursors") if isinstance(paging, dict) else None
        next_after = cursors.get("after") if isinstance(cursors, dict) else None
        if not isinstance(next_after, str) or not next_after or next_after == after:
            break
        after = next_after

    return media


def _account_insights(
    account: SocialAccount,
    days: int,
    client: httpx.Client,
) -> dict:
    access_token = _instagram_access_token(account, client)
    version = os.getenv("INSTAGRAM_API_VERSION", "v23.0").strip("/")
    base_url = f"{INSTAGRAM_GRAPH_URL}/{version}/{account.provider_account_id}"
    until = datetime.now(timezone.utc)
    since = until - timedelta(days=days)

    profile = _response_json(
        client.get(
            base_url,
            params={
                "fields": "id,username,name,followers_count,media_count",
                "access_token": access_token,
            },
        )
    )
    daily, unavailable_metrics = _account_insight_series(
        base_url, access_token, since, until, client
    )
    media = _account_media(base_url, access_token, since, client)

    reach = sum(_integer(point["reach"]) for point in daily)
    impressions = sum(_integer(point["impressions"]) for point in daily)
    reported_interactions = sum(_integer(point["interactions"]) for point in daily)
    media_interactions = sum(_integer(item["interactions"]) for item in media)
    interactions = reported_interactions or media_interactions

    return {
        "account_name": account.account_name,
        "username": account.username,
        "followers": _integer(profile.get("followers_count")),
        "media_count": _integer(profile.get("media_count")),
        "reach": reach,
        "impressions": impressions,
        "profile_views": sum(_integer(point["profile_views"]) for point in daily),
        "followers_gained": sum(_integer(point["followers_gained"]) for point in daily),
        "likes": sum(_integer(item["likes"]) for item in media),
        "comments": sum(_integer(item["comments"]) for item in media),
        "shares": sum(_integer(point["shares"]) for point in daily),
        "saves": sum(_integer(point["saves"]) for point in daily),
        "interactions": interactions,
        "engagement_rate": round(interactions / reach * 100, 2) if reach else 0,
        "daily": daily,
        "media": media,
        "unavailable_metrics": unavailable_metrics,
    }


def instagram_metrics(
    database: Session,
    accounts: list[SocialAccount],
    days: int,
) -> tuple[dict | None, str]:
    live_accounts = [
        account
        for account in accounts
        if account.provider == "instagram"
        and not account.provider_account_id.startswith("local-instagram-")
    ]
    if not live_accounts:
        return None, "Connect a live Instagram professional account to load provider insights."

    results = []
    errors = []
    with httpx.Client(timeout=20.0) as client:
        for account in live_accounts:
            try:
                results.append(_account_insights(account, days, client))
            except httpx.HTTPError:
                errors.append("Instagram could not be reached while loading insights.")
            except (InstagramInsightsError, RuntimeError) as error:
                errors.append(str(error))
    database.commit()
    if not results:
        reason = errors[0] if errors else "Instagram insights are temporarily unavailable."
        return None, reason

    daily_totals: dict[str, dict[str, int]] = defaultdict(
        lambda: {
            "reach": 0,
            "impressions": 0,
            "profile_views": 0,
            "followers_gained": 0,
            "interactions": 0,
            "shares": 0,
            "saves": 0,
        }
    )
    media = []
    unavailable_metrics: set[str] = set()
    for result in results:
        for item in result["media"]:
            media.append(
                {
                    **item,
                    "account_name": result["account_name"],
                    "username": result["username"],
                }
            )
        unavailable_metrics.update(result["unavailable_metrics"])
        for point in result["daily"]:
            for key in daily_totals[str(point["date"])]:
                daily_totals[str(point["date"])][key] += _integer(point[key])

    content = sorted(media, key=lambda item: item["published_at"], reverse=True)
    top_media = sorted(
        media,
        key=lambda item: (item["interactions"], item["published_at"]),
        reverse=True,
    )[:8]
    reach = sum(result["reach"] for result in results)
    interactions = sum(result["interactions"] for result in results)
    metrics = {
        "source": "instagram",
        "accounts": len(results),
        "range_days": days,
        "followers": sum(result["followers"] for result in results),
        "followers_gained": sum(result["followers_gained"] for result in results),
        "account_media_count": sum(result["media_count"] for result in results),
        "posts_analyzed": len(content),
        "reach": reach,
        "impressions": sum(result["impressions"] for result in results),
        "impressions_source": "views",
        "profile_views": sum(result["profile_views"] for result in results),
        "likes": sum(result["likes"] for result in results),
        "comments": sum(result["comments"] for result in results),
        "shares": sum(result["shares"] for result in results),
        "saves": sum(result["saves"] for result in results),
        "interactions": interactions,
        "engagement_rate": round(interactions / reach * 100, 2) if reach else 0,
        "daily": [
            {"date": date, **values} for date, values in sorted(daily_totals.items())
        ],
        "top_media": top_media,
        "content": content[:100],
        "unavailable_metrics": sorted(unavailable_metrics),
        "fetched_at": datetime.now(timezone.utc).isoformat(),
    }
    reason = ""
    notices = []
    if errors:
        notices.append(f"{len(errors)} connected account(s) could not be refreshed")
    if unavailable_metrics:
        notices.append("some Instagram metrics were unavailable")
    if notices:
        reason = f"Loaded {len(results)} account(s); {'; '.join(notices)}."
    return metrics, reason
