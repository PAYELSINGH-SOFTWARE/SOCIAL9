import asyncio
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import inspect, text

from . import models
from .database import Base, SessionLocal, engine
from .publisher import PublishError, publish_post
from .router.accounts import router as accounts_router
from .router.analytics import router as analytics_router
from .router.auth import router as auth_router
from .router.posts import router as posts_router

Base.metadata.create_all(bind=engine)

# Lightweight migrations for existing local SQLite databases.
existing_columns = {column["name"] for column in inspect(engine).get_columns("posts")}
column_migrations = {
    "media_urls": "ALTER TABLE posts ADD COLUMN media_urls TEXT NOT NULL DEFAULT '[]'",
    "external_post_ids": "ALTER TABLE posts ADD COLUMN external_post_ids TEXT NOT NULL DEFAULT '{}'",
    "publish_error": "ALTER TABLE posts ADD COLUMN publish_error TEXT",
    "published_at": "ALTER TABLE posts ADD COLUMN published_at DATETIME",
}
with engine.begin() as connection:
    for name, statement in column_migrations.items():
        if name not in existing_columns:
            connection.execute(text(statement))


def publish_due_posts():
    db = SessionLocal()
    try:
        due_posts = (
            db.query(models.Post)
            .filter(
                models.Post.status == "scheduled",
                models.Post.scheduled_for <= datetime.now(timezone.utc),
            )
            .all()
        )
        for post in due_posts:
            try:
                publish_post(db, post)
            except PublishError:
                # publish_post records the provider error on the post.
                continue
    finally:
        db.close()


async def scheduler_loop():
    while True:
        await asyncio.to_thread(publish_due_posts)
        await asyncio.sleep(30)


@asynccontextmanager
async def lifespan(app: FastAPI):
    scheduler = asyncio.create_task(scheduler_loop())
    try:
        yield
    finally:
        scheduler.cancel()
        try:
            await scheduler
        except asyncio.CancelledError:
            pass


app = FastAPI(title="vCueSocial9 API", version="0.2.0", lifespan=lifespan)
uploads_directory = Path(__file__).resolve().parent / "uploads"
uploads_directory.mkdir(exist_ok=True)
app.mount("/uploads", StaticFiles(directory=uploads_directory), name="uploads")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[],
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", tags=["System"])
def health():
    return {"status": "ok"}


app.include_router(auth_router, prefix="/auth", tags=["Authentication"])
app.include_router(posts_router, prefix="/posts", tags=["Posts"])
app.include_router(accounts_router, prefix="/accounts", tags=["Connected accounts"])
app.include_router(analytics_router, prefix="/analytics", tags=["Analytics"])
