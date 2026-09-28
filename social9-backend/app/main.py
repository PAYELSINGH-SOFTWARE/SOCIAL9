import asyncio
import contextlib
import logging
import os
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

load_dotenv()

logger = logging.getLogger(__name__)

from .auth import router as auth_router
from .analytics import router as analytics_router
from .ai import router as ai_router
from .billing import router as billing_router
from .database import SessionLocal
from .models import User
from .security import hash_password
from .social_accounts import router as social_accounts_router
from .media_storage import UPLOADS_DIRECTORY
from .meta_compliance import router as meta_compliance_router
from .posts import router as posts_router
from .publishing import process_due_posts
from .workspace import router as workspace_router


def configured_cors_origins() -> list[str]:
    """Return local and explicitly configured browser origins."""
    origins = {
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "https://social9-web.vercel.app",
    }

    for value in (
        os.getenv("FRONTEND_URL", ""),
        *os.getenv("CORS_ORIGINS", "").split(","),
    ):
        origin = value.strip().rstrip("/")
        if origin:
            origins.add(origin)

    return sorted(origins)


def seed_demo_user() -> None:
    if os.getenv("SEED_DEMO_USER", "false").lower() != "true":
        return

    email = os.getenv("DEMO_USER_EMAIL", "demo@social9.in").strip().lower()
    password = os.getenv("DEMO_USER_PASSWORD", "Social9Demo!")
    database = SessionLocal()

    try:
        if database.query(User).filter(User.email == email).first() is None:
            database.add(
                User(
                    name="Social9 Demo",
                    email=email,
                    hashed_password=hash_password(password),
                    is_verified=True,
                )
            )
            database.commit()
    finally:
        database.close()


@asynccontextmanager
async def lifespan(_: FastAPI):
    seed_demo_user()
    stop_event = asyncio.Event()
    scheduler_task = None

    async def publishing_loop() -> None:
        interval = max(
            10,
            int(os.getenv("PUBLISHING_SCHEDULER_INTERVAL_SECONDS", "30")),
        )

        while not stop_event.is_set():
            database = SessionLocal()

            try:
                await asyncio.to_thread(process_due_posts, database)
            except Exception:
                database.rollback()
                logger.exception("Scheduled publishing pass failed")
            finally:
                database.close()

            try:
                await asyncio.wait_for(stop_event.wait(), timeout=interval)
            except TimeoutError:
                pass

    scheduler_default = "true" if os.getenv("RENDER_EXTERNAL_URL") else "false"

    if (
        os.getenv("PUBLISHING_SCHEDULER_ENABLED", scheduler_default).lower()
        == "true"
    ):
        scheduler_task = asyncio.create_task(publishing_loop())

    try:
        yield
    finally:
        stop_event.set()

        if scheduler_task:
            scheduler_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await scheduler_task


app = FastAPI(
    title="Social9 API",
    description="Authentication API for the Social9 web application.",
    version="0.1.0",
    lifespan=lifespan,
)

UPLOADS_DIRECTORY.mkdir(exist_ok=True)
app.mount("/uploads", StaticFiles(directory=UPLOADS_DIRECTORY), name="uploads")

app.add_middleware(
    CORSMiddleware,
    allow_origins=configured_cors_origins(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", tags=["System"])
def home() -> dict[str, str]:
    return {
        "message": "Social9 backend is running",
        "docs": "/docs",
        "health": "/health",
    }


@app.head("/", include_in_schema=False)
def home_head() -> Response:
    return Response(status_code=200)


@app.get("/health", tags=["System"])
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(auth_router)
app.include_router(social_accounts_router)
app.include_router(posts_router)
app.include_router(analytics_router)
app.include_router(billing_router)
app.include_router(ai_router)
app.include_router(workspace_router)
app.include_router(meta_compliance_router)