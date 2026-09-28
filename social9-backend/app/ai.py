from fastapi import APIRouter, Depends

from .ai_schemas import AIAssistRequest, AIAssistResponse
from .auth import get_current_user
from .models import User


router = APIRouter(prefix="/ai", tags=["AI Assistant"])


def generate_preview(data: AIAssistRequest) -> AIAssistResponse:
    topic = data.topic.rstrip(".")
    channel = "Instagram and LinkedIn" if data.platform == "both" else data.platform.title()
    if data.action == "caption":
        content = f"Make {topic} part of your next routine. Thoughtful details, made for real people. Discover what is new at Social9."
        suggestions = ["Add a clear call to action", "Mention a local detail", "Pair with a product or team photo"]
    elif data.action == "improve":
        content = f"Here is a sharper take on your idea: {topic}. Keep it useful, human, and easy to act on."
        suggestions = ["Lead with the customer benefit", "Use one specific proof point", "End with one simple next step"]
    elif data.action == "hashtags":
        content = "#LocalBusiness #SmallBusiness #SocialMediaMarketing #ContentStrategy #BusinessGrowth"
        suggestions = ["Use 3-5 highly relevant tags", "Mix local and industry tags", "Avoid repeating the same set every time"]
    else:
        content = f"{topic}. Simple, useful, and ready for {channel}."
        suggestions = ["Keep the first sentence as the hook", "Remove filler words", "Test the shorter version against your original"]
    return AIAssistResponse(action=data.action, content=content, suggestions=suggestions, simulated=True)


@router.post("/assist", response_model=AIAssistResponse)
def assist(
    data: AIAssistRequest,
    _: User = Depends(get_current_user),
) -> AIAssistResponse:
    return generate_preview(data)
