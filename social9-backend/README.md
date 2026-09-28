# Social9 Backend

Shared FastAPI backend for the Social9 website and future Flutter application.

## Current foundation

- Email and password authentication
- Secure PBKDF2 password hashing
- JWT access tokens
- User signup and profile endpoints
- Email-verification and password-reset token flows
- PostgreSQL through SQLAlchemy and psycopg 3
- Alembic-managed database migrations
- SQLite-backed isolated automated tests
- Provider-independent Instagram and LinkedIn account connections
- Encrypted social access/refresh-token storage and single-use OAuth state
- Website post composer APIs for drafts, media attachments and scheduling
- Calendar range queries and post rescheduling/draft management
- Authenticated simulated analytics for local dashboard development
- Provider-neutral subscriptions and server-enforced paid feature entitlements
- S3-compatible persistent media storage with a local development fallback
- Signed Meta deauthorization and user-data deletion callbacks

## Local development

```powershell
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload --port 8000
```

The API runs at `http://127.0.0.1:8000`, with documentation at `http://127.0.0.1:8000/docs`.

## Deploy to Render

This repository includes `render.yaml` with the production build, migration,
start, and health-check commands. Create a Render Web Service from this
repository (or use the blueprint), then set the secret environment variables
listed in the file. Set `DATABASE_URL` to the existing Render PostgreSQL
internal URL and set `FRONTEND_URL`/`CORS_ORIGINS` to the deployed Vercel URL.
The start command applies pending Alembic migrations before starting FastAPI.
Render supplies the backend's public URL automatically, so mock OAuth callbacks
also work on the hosted service without hard-coded callback addresses.

Copy `.env.example` to `.env` before configuring non-development credentials. Never commit database credentials or provider secrets.

Apply all database migrations before starting the API:

```powershell
python -m alembic upgrade head
```

## Social account development

Keep `OAUTH_MOCK_MODE=true` to exercise the complete connection flow locally
without Meta or LinkedIn credentials. The mock callback creates only local test
records; it never contacts either provider. Provider-specific overrides allow
one integration to go live independently. Set `FRONTEND_URL` to the website
origin and use a dedicated Fernet `TOKEN_ENCRYPTION_KEY` outside local
development.

Instagram API with Instagram Login is implemented with Meta's authorization
code flow. It exchanges the code for a short-lived token, upgrades it to a
long-lived Instagram token, reads the professional profile, and encrypts the
token before storage. Tokens nearing expiry are renewed through Meta's refresh
endpoint before publishing. The flow uses direct Instagram Business Login and
therefore supports Instagram Business and Creator accounts without requiring a
linked Facebook Page. To enable it, configure `INSTAGRAM_CLIENT_ID` and
`INSTAGRAM_CLIENT_SECRET` using the Instagram App ID and Instagram App Secret
shown under **Instagram > API setup with Instagram login > Business login
settings** (not the general Meta App ID and App Secret). Add the exact approved
`INSTAGRAM_REDIRECT_URI`, then
set `INSTAGRAM_OAUTH_MOCK_MODE=false`. Request only
`instagram_business_basic,instagram_business_content_publish,instagram_business_manage_insights`;
the analytics endpoint reads account reach/profile views and media engagement
only after the user grants the insights permission. Production use
for accounts outside the Meta app's test roles requires Advanced Access through
Meta App Review. LinkedIn can remain in preview mode with
`LINKEDIN_OAUTH_MOCK_MODE=true` until its separate token exchange is enabled.

Keep `BILLING_MOCK_MODE=true` to preview free and paid feature states locally.
The mock subscription endpoints are unavailable when this flag is disabled.
No payment provider is connected yet, and the growth forecasting model remains
outside this repository. Its future API can reuse the existing server-side
`require_growth_projection_access` dependency.

Drafts and scheduled posts are stored in the configured database. Media uses
the ignored local `uploads` directory when `MEDIA_STORAGE_BACKEND=local`. For
production, set `MEDIA_STORAGE_BACKEND=s3` and configure `S3_BUCKET`,
`S3_PUBLIC_BASE_URL`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and
`AWS_REGION`. Set `S3_ENDPOINT_URL` for an S3-compatible service such as
Cloudflare R2. The public base URL must permit anonymous reads of individual
objects because Instagram downloads the image during publishing; bucket
listing and write access should remain private.

Meta compliance callbacks verify the request signature with `META_APP_SECRET`
or, when it is not separately configured, `INSTAGRAM_CLIENT_SECRET`. Configure
these exact production URLs in the Meta app's Business Login settings:

- Deauthorize callback: `https://social9-backend-ghqu.onrender.com/meta/instagram/deauthorize`
- Data deletion request: `https://social9-backend-ghqu.onrender.com/meta/instagram/data-deletion`
- Public deletion instructions: `https://social9-web.vercel.app/data-deletion`

The deletion callback immediately removes the Instagram identifier, profile
connection, and encrypted access token, then returns Meta's required public
status URL and confirmation code. It is idempotent, so repeated valid requests
also return a completed result.

For local access to Render PostgreSQL, use its external database URL with
`sslmode=require`. A backend deployed on Render should use the internal database
URL supplied through its `DATABASE_URL` environment variable.

## Optional prototype login

The demo user is disabled by default. It is available only when
`SEED_DEMO_USER=true` is explicitly configured in a disposable development
database.

- Email: `demo@social9.in`
- Password: `Social9Demo!`

For local UI development only, `EXPOSE_DEV_AUTH_TOKENS=true` returns short-lived
verification and reset tokens in API responses. Keep it `false` outside a
disposable development environment; production delivery will use an approved
email provider.
