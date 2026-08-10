import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import RedirectResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError
from jose import jwt
from pydantic import BaseModel, field_validator
from sqlalchemy.orm import Session

from ..database import SessionLocal
from ..models import User


router = APIRouter()
bearer_scheme = HTTPBearer()


# ============================================================
# SOCIAL9 AUTH SETTINGS
# ============================================================

SECRET_KEY = os.getenv(
    "SOCIAL9_SECRET_KEY",
    "development-only-change-me",
)

ALGORITHM = "HS256"

ACCESS_TOKEN_EXPIRE_MINUTES = int(
    os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "10080")
)


# ============================================================
# LINKEDIN SETTINGS
# ============================================================

LINKEDIN_CLIENT_ID = os.getenv("LINKEDIN_CLIENT_ID")
LINKEDIN_CLIENT_SECRET = os.getenv("LINKEDIN_CLIENT_SECRET")

LINKEDIN_REDIRECT_URI = os.getenv(
    "LINKEDIN_REDIRECT_URI",
    "https://social9-1.onrender.com/auth/linkedin/callback",
)

LINKEDIN_AUTHORIZATION_URL = (
    "https://www.linkedin.com/oauth/v2/authorization"
)

LINKEDIN_TOKEN_URL = (
    "https://www.linkedin.com/oauth/v2/accessToken"
)

LINKEDIN_USERINFO_URL = (
    "https://api.linkedin.com/v2/userinfo"
)

# OIDC login + permission to create/share LinkedIn posts.
LINKEDIN_SCOPES = "openid profile email w_member_social"

# Flutter deep link.
# We will configure Flutter/Android for this later.
FLUTTER_LINKEDIN_CALLBACK = "social9://linkedin/callback"


# ============================================================
# PASSWORD FUNCTIONS
# ============================================================

def hash_password(password: str):
    salt = os.urandom(16)

    password_hash = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        100_000,
    )

    return f"{salt.hex()}:{password_hash.hex()}"


def verify_password(
    plain_password: str,
    hashed_password: str,
):
    try:
        salt_hex, stored_hash_hex = hashed_password.split(":", 1)

        salt = bytes.fromhex(salt_hex)
        stored_hash = bytes.fromhex(stored_hash_hex)

    except ValueError:
        return False

    password_hash = hashlib.pbkdf2_hmac(
        "sha256",
        plain_password.encode("utf-8"),
        salt,
        100_000,
    )

    return hmac.compare_digest(
        password_hash,
        stored_hash,
    )


# ============================================================
# JWT
# ============================================================

def create_access_token(data: dict):
    to_encode = data.copy()

    expire = (
        datetime.now(timezone.utc)
        + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    )

    to_encode.update({"exp": expire})

    return jwt.encode(
        to_encode,
        SECRET_KEY,
        algorithm=ALGORITHM,
    )


# ============================================================
# DATABASE
# ============================================================

def get_db():
    db = SessionLocal()

    try:
        yield db

    finally:
        db.close()


# ============================================================
# CURRENT USER
# ============================================================

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(
        bearer_scheme
    ),
    db: Session = Depends(get_db),
):
    try:
        payload = jwt.decode(
            credentials.credentials,
            SECRET_KEY,
            algorithms=[ALGORITHM],
        )

        email = payload.get("sub")

        if not email:
            raise JWTError("Missing subject")

    except JWTError as exc:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired token",
        ) from exc

    user = (
        db.query(User)
        .filter(User.email == email)
        .first()
    )

    if user is None:
        raise HTTPException(
            status_code=401,
            detail="User no longer exists",
        )

    return user


# ============================================================
# ME
# ============================================================

@router.get("/me")
def me(
    user: User = Depends(get_current_user),
):
    return {
        "id": user.id,
        "name": user.name,
        "email": user.email,
    }


# ============================================================
# SIGNUP
# ============================================================

class SignupRequest(BaseModel):
    name: str
    email: str
    password: str

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str):
        value = value.strip()

        if len(value) < 2:
            raise ValueError(
                "Name must be at least 2 characters"
            )

        return value

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str):
        value = value.strip().lower()

        if (
            "@" not in value
            or value.startswith("@")
            or value.endswith("@")
        ):
            raise ValueError(
                "Enter a valid email address"
            )

        return value

    @field_validator("password")
    @classmethod
    def validate_password(cls, value: str):
        if len(value) < 8:
            raise ValueError(
                "Password must be at least 8 characters"
            )

        return value


# ============================================================
# LOGIN
# ============================================================

class LoginRequest(BaseModel):
    email: str
    password: str

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str):
        return value.strip().lower()


# ============================================================
# NORMAL SIGNUP
# ============================================================

@router.post("/signup", status_code=201)
async def signup(
    data: SignupRequest,
    db: Session = Depends(get_db),
):
    existing_user = (
        db.query(User)
        .filter(User.email == data.email)
        .first()
    )

    if existing_user:
        raise HTTPException(
            status_code=409,
            detail="Email already registered",
        )

    new_user = User(
        name=data.name,
        email=data.email,
        hashed_password=hash_password(data.password),
    )

    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    return {
        "message": "User created successfully",
        "user": {
            "id": new_user.id,
            "name": new_user.name,
            "email": new_user.email,
        },
    }


# ============================================================
# NORMAL LOGIN
# ============================================================

@router.post("/login")
async def login(
    data: LoginRequest,
    db: Session = Depends(get_db),
):
    user = (
        db.query(User)
        .filter(User.email == data.email)
        .first()
    )

    if (
        user is None
        or not verify_password(
            data.password,
            user.hashed_password,
        )
    ):
        raise HTTPException(
            status_code=401,
            detail="Invalid email or password",
        )

    access_token = create_access_token(
        data={"sub": user.email}
    )

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "name": user.name,
            "email": user.email,
        },
    }


# ============================================================
# LINKEDIN LOGIN
# ============================================================

@router.get("/linkedin/login")
async def linkedin_login():
    if not LINKEDIN_CLIENT_ID:
        raise HTTPException(
            status_code=500,
            detail="LINKEDIN_CLIENT_ID is not configured",
        )

    if not LINKEDIN_CLIENT_SECRET:
        raise HTTPException(
            status_code=500,
            detail="LINKEDIN_CLIENT_SECRET is not configured",
        )

    # Create a signed state value.
    state_payload = {
        "nonce": secrets.token_urlsafe(24),
        "exp": datetime.now(timezone.utc)
        + timedelta(minutes=10),
    }

    state = jwt.encode(
        state_payload,
        SECRET_KEY,
        algorithm=ALGORITHM,
    )

    params = {
        "response_type": "code",
        "client_id": LINKEDIN_CLIENT_ID,
        "redirect_uri": LINKEDIN_REDIRECT_URI,
        "state": state,
        "scope": LINKEDIN_SCOPES,
    }

    authorization_url = (
        LINKEDIN_AUTHORIZATION_URL
        + "?"
        + urlencode(params)
    )

    return RedirectResponse(
        url=authorization_url,
        status_code=302,
    )


# ============================================================
# LINKEDIN CALLBACK
# ============================================================

@router.get("/linkedin/callback")
async def linkedin_callback(
    code: str | None = Query(default=None),
    state: str | None = Query(default=None),
    error: str | None = Query(default=None),
    error_description: str | None = Query(default=None),
    db: Session = Depends(get_db),
):
    # --------------------------------------------------------
    # LinkedIn rejected authorization
    # --------------------------------------------------------

    if error:
        message = error_description or error

        raise HTTPException(
            status_code=400,
            detail=f"LinkedIn authorization failed: {message}",
        )

    if not code:
        raise HTTPException(
            status_code=400,
            detail="LinkedIn authorization code is missing",
        )

    if not state:
        raise HTTPException(
            status_code=400,
            detail="LinkedIn state is missing",
        )

    # --------------------------------------------------------
    # Verify state
    # --------------------------------------------------------

    try:
        jwt.decode(
            state,
            SECRET_KEY,
            algorithms=[ALGORITHM],
        )

    except JWTError as exc:
        raise HTTPException(
            status_code=400,
            detail="Invalid or expired LinkedIn state",
        ) from exc

    # --------------------------------------------------------
    # Make sure credentials exist
    # --------------------------------------------------------

    if not LINKEDIN_CLIENT_ID:
        raise HTTPException(
            status_code=500,
            detail="LINKEDIN_CLIENT_ID is not configured",
        )

    if not LINKEDIN_CLIENT_SECRET:
        raise HTTPException(
            status_code=500,
            detail="LINKEDIN_CLIENT_SECRET is not configured",
        )

    # --------------------------------------------------------
    # Exchange authorization code for access token
    # --------------------------------------------------------

    token_data = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": LINKEDIN_REDIRECT_URI,
        "client_id": LINKEDIN_CLIENT_ID,
        "client_secret": LINKEDIN_CLIENT_SECRET,
    }

    async with httpx.AsyncClient(timeout=30.0) as client:

        token_response = await client.post(
            LINKEDIN_TOKEN_URL,
            data=token_data,
            headers={
                "Content-Type": "application/x-www-form-urlencoded"
            },
        )

    if token_response.status_code != 200:
        raise HTTPException(
            status_code=400,
            detail={
                "message": "Unable to get LinkedIn access token",
                "linkedin_response": token_response.text,
            },
        )

    token_json = token_response.json()

    access_token = token_json.get("access_token")

    if not access_token:
        raise HTTPException(
            status_code=400,
            detail="LinkedIn did not return an access token",
        )

    # --------------------------------------------------------
    # Get LinkedIn user information using OpenID Connect
    # --------------------------------------------------------

    async with httpx.AsyncClient(timeout=30.0) as client:

        userinfo_response = await client.get(
            LINKEDIN_USERINFO_URL,
            headers={
                "Authorization": f"Bearer {access_token}",
            },
        )

    if userinfo_response.status_code != 200:
        raise HTTPException(
            status_code=400,
            detail={
                "message": "Unable to get LinkedIn user information",
                "linkedin_response": userinfo_response.text,
            },
        )

    linkedin_user = userinfo_response.json()

    linkedin_id = linkedin_user.get("sub")
    linkedin_name = linkedin_user.get("name")
    linkedin_email = linkedin_user.get("email")

    if not linkedin_id:
        raise HTTPException(
            status_code=400,
            detail="LinkedIn user ID was not returned",
        )

    if not linkedin_email:
        raise HTTPException(
            status_code=400,
            detail="LinkedIn email was not returned",
        )

    # --------------------------------------------------------
    # Find existing Social9 user
    # --------------------------------------------------------

    user = (
        db.query(User)
        .filter(User.email == linkedin_email.lower())
        .first()
    )

    # --------------------------------------------------------
    # Create Social9 account if user doesn't exist
    # --------------------------------------------------------

    if user is None:

        temporary_password = secrets.token_urlsafe(32)

        user = User(
            name=linkedin_name or "LinkedIn User",
            email=linkedin_email.lower(),
            hashed_password=hash_password(
                temporary_password
            ),
        )

        db.add(user)
        db.commit()
        db.refresh(user)

    # --------------------------------------------------------
    # Create Social9 JWT
    # --------------------------------------------------------

    social9_token = create_access_token(
        data={"sub": user.email}
    )

    # --------------------------------------------------------
    # Return to Flutter
    # --------------------------------------------------------

    redirect_params = urlencode(
        {
            "token": social9_token,
            "id": user.id,
            "name": user.name,
            "email": user.email,
        }
    )

    flutter_redirect = (
        FLUTTER_LINKEDIN_CALLBACK
        + "?"
        + redirect_params
    )

    return RedirectResponse(
        url=flutter_redirect,
        status_code=302,
    )