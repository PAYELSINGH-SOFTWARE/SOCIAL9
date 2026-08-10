import asyncio
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import inspect, text

from . import models
from .database import Base, SessionLocal, engine
from .publisher import PublishError, publish_post
from .router.accounts import router as accounts_router
from .router.analytics import router as analytics_router
from .router.auth import router as auth_router
from .router.posts import router as posts_router


# ============================================================
# DATABASE
# ============================================================

Base.metadata.create_all(bind=engine)


# Lightweight migrations for existing local SQLite databases.

existing_columns = {
    column["name"]
    for column in inspect(engine).get_columns("posts")
}

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


# ============================================================
# SCHEDULED POST PUBLISHING
# ============================================================

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


# ============================================================
# APPLICATION LIFESPAN
# ============================================================

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


# ============================================================
# FASTAPI APPLICATION
# ============================================================

app = FastAPI(
    title="vCueSocial9 API",
    version="0.2.0",
    lifespan=lifespan,
)


# ============================================================
# UPLOADS
# ============================================================

uploads_directory = Path(__file__).resolve().parent / "uploads"
uploads_directory.mkdir(exist_ok=True)

app.mount(
    "/uploads",
    StaticFiles(directory=uploads_directory),
    name="uploads",
)


# ============================================================
# CORS
# ============================================================

app.add_middleware(
    CORSMiddleware,
    allow_origins=[],
    allow_origin_regex=r"^https?://(localhost|127.0.0.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================
# ROOT ROUTE
# ============================================================

@app.get("/", tags=["System"])
def root():
    return {
        "message": "Social9 API is running",
        "status": "ok",
        "version": "0.2.0",
    }


# ============================================================
# HEALTH CHECK
# ============================================================

@app.get("/health", tags=["System"])
def health():
    return {"status": "ok"}


# ============================================================
# SOCIAL9 PRIVACY POLICY
# ============================================================

@app.get(
    "/privacy-policy",
    response_class=HTMLResponse,
    tags=["System"],
)
def privacy_policy():
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Social9 Privacy Policy</title>

        <meta
            name="viewport"
            content="width=device-width, initial-scale=1.0"
        >

        <style>
            body {
                font-family: Arial, sans-serif;
                max-width: 900px;
                margin: 40px auto;
                padding: 20px;
                line-height: 1.6;
                color: #222;
                background: #ffffff;
            }

            h1 {
                color: #111111;
                margin-bottom: 10px;
            }

            h2 {
                margin-top: 30px;
                color: #222222;
            }

            p {
                font-size: 16px;
            }
        </style>
    </head>

    <body>

        <h1>Social9 Privacy Policy</h1>

        <p>
            <strong>Last updated:</strong> August 10, 2026
        </p>

        <h2>1. Introduction</h2>

        <p>
            Social9 is a social media management application that allows
            users to manage and connect supported social media accounts.
            We respect your privacy and are committed to protecting your
            personal information.
        </p>

        <h2>2. Information We Collect</h2>

        <p>
            Social9 may collect information such as your name, email
            address, account credentials, and information required to
            connect supported social media accounts.
        </p>

        <h2>3. How We Use Your Information</h2>

        <p>
            We use your information to create and manage your Social9
            account, authenticate users, provide application features,
            and allow you to connect and manage supported social media
            accounts.
        </p>

        <h2>4. Social Media Accounts</h2>

        <p>
            If you choose to connect a social media account such as
            LinkedIn, Social9 may receive information that the social
            media platform makes available through its authorized APIs
            and according to the permissions you grant.
        </p>

        <h2>5. Data Storage</h2>

        <p>
            Account information and application data may be stored in
            our database for the purpose of providing Social9 services.
        </p>

        <h2>6. Data Sharing</h2>

        <p>
            Social9 does not sell your personal information to third
            parties. Information may be shared with third-party
            platforms only when necessary to provide features that
            you have requested and authorized.
        </p>

        <h2>7. Security</h2>

        <p>
            We take reasonable measures to protect your information
            against unauthorized access, alteration, disclosure, or
            destruction.
        </p>

        <h2>8. Account Deletion</h2>

        <p>
            Users may request deletion of their Social9 account and
            associated personal information by contacting the Social9
            team.
        </p>

        <h2>9. Changes to This Privacy Policy</h2>

        <p>
            We may update this Privacy Policy from time to time.
            Changes will be published on this page.
        </p>

        <h2>10. Contact Us</h2>

        <p>
            For questions regarding this Privacy Policy or your personal
            information, please contact the Social9 team.
        </p>

    </body>
    </html>
    """


# ============================================================
# EXISTING SOCIAL9 ROUTERS
# ============================================================

app.include_router(
    auth_router,
    prefix="/auth",
    tags=["Authentication"],
)

app.include_router(
    posts_router,
    prefix="/posts",
    tags=["Posts"],
)

app.include_router(
    accounts_router,
    prefix="/accounts",
    tags=["Connected accounts"],
)

app.include_router(
    analytics_router,
    prefix="/analytics",
    tags=["Analytics"],
)