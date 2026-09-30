import os
from collections.abc import Generator

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from sqlalchemy import text
from sqlalchemy.orm import Session

from .database import SessionLocal
from .models import User
from .schemas import (
    ActionResponse,
    EmailRequest,
    LoginRequest,
    LoginResponse,
    PasswordResetRequest,
    SignupRequest,
    SignupResponse,
    TokenRequest,
    UserResponse,
)
from .security import (
    ALGORITHM,
    SECRET_KEY,
    create_access_token,
    create_action_token,
    decode_action_token,
    hash_password,
    password_fingerprint,
    verify_password,
)


router = APIRouter(prefix="/auth", tags=["Authentication"])
bearer_scheme = HTTPBearer()


def expose_dev_tokens() -> bool:
    return os.getenv("EXPOSE_DEV_AUTH_TOKENS", "false").lower() == "true"


def email_verification_enabled() -> bool:
    """Allow the shared API to support the original Social9 users table."""
    return os.getenv("EMAIL_VERIFICATION_ENABLED", "true").lower() == "true"


def user_response(user: User) -> UserResponse:
    return UserResponse(
        id=user.id,
        name=user.name,
        email=user.email,
        is_verified=user.is_verified if email_verification_enabled() else True,
    )


def get_db() -> Generator[Session, None, None]:
    database = SessionLocal()
    try:
        yield database
    finally:
        database.close()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    database: Session = Depends(get_db),
) -> User:
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        email = payload.get("sub")
        if not email or payload.get("purpose") != "access":
            raise JWTError("Missing token subject")
    except JWTError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        ) from error

    user = database.query(User).filter(User.email == email).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User no longer exists",
        )
    return user


@router.post("/login", response_model=LoginResponse)
def login(data: LoginRequest, database: Session = Depends(get_db)) -> LoginResponse:
    user = database.query(User).filter(User.email == data.email).first()
    if user is None or not verify_password(data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    if email_verification_enabled() and not user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Verify your email before signing in",
        )

    return LoginResponse(
        access_token=create_access_token(user.email),
        user=user_response(user),
    )


@router.post("/signup", response_model=SignupResponse, status_code=status.HTTP_201_CREATED)
def signup(data: SignupRequest, database: Session = Depends(get_db)) -> SignupResponse:
    if database.query(User).filter(User.email == data.email).first():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered",
        )

    password_hash = hash_password(data.password)
    verification_enabled = email_verification_enabled()
    if verification_enabled:
        user = User(
            name=data.name,
            email=data.email,
            hashed_password=password_hash,
            is_verified=False,
        )
        database.add(user)
        database.commit()
        database.refresh(user)
        verification_token = create_action_token(user.email, "verify_email")
    else:
        database.execute(
            text(
                "INSERT INTO users (name, email, hashed_password) "
                "VALUES (:name, :email, :hashed_password)"
            ),
            {
                "name": data.name,
                "email": data.email,
                "hashed_password": password_hash,
            },
        )
        database.commit()
        user = database.query(User).filter(User.email == data.email).one()
        verification_token = None
    return SignupResponse(
        message=(
            "Account created. Verify your email before signing in."
            if verification_enabled
            else "Account created. You can now sign in."
        ),
        user=user_response(user),
        verification_token=verification_token if expose_dev_tokens() else None,
    )


@router.post("/verification/request", response_model=ActionResponse)
def request_verification(
    data: EmailRequest, database: Session = Depends(get_db)
) -> ActionResponse:
    if not email_verification_enabled():
        return ActionResponse(message="Email verification is not required.")

    user = database.query(User).filter(User.email == data.email).first()
    token = None
    if user is not None and not user.is_verified:
        generated_token = create_action_token(user.email, "verify_email")
        token = generated_token if expose_dev_tokens() else None
    return ActionResponse(
        message="If the account needs verification, instructions are ready.",
        token=token,
    )


@router.post("/verify-email", response_model=ActionResponse)
def verify_email(data: TokenRequest, database: Session = Depends(get_db)) -> ActionResponse:
    if not email_verification_enabled():
        return ActionResponse(message="Email verification is not required.")

    try:
        payload = decode_action_token(data.token, "verify_email")
        email = payload["sub"]
    except (JWTError, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Verification link is invalid or expired",
        ) from error

    user = database.query(User).filter(User.email == email).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Verification link is invalid or expired",
        )
    user.is_verified = True
    database.commit()
    return ActionResponse(message="Email verified. You can now sign in.")


@router.post("/password/forgot", response_model=ActionResponse)
def forgot_password(
    data: EmailRequest, database: Session = Depends(get_db)
) -> ActionResponse:
    user = database.query(User).filter(User.email == data.email).first()
    token = None
    if user is not None:
        generated_token = create_action_token(
            user.email,
            "reset_password",
            {"credential": password_fingerprint(user.hashed_password)},
        )
        token = generated_token if expose_dev_tokens() else None
    return ActionResponse(
        message="If an account exists, password reset instructions are ready.",
        token=token,
    )


@router.post("/password/reset", response_model=ActionResponse)
def reset_password(
    data: PasswordResetRequest, database: Session = Depends(get_db)
) -> ActionResponse:
    try:
        payload = decode_action_token(data.token, "reset_password")
        email = payload["sub"]
    except (JWTError, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password reset link is invalid or expired",
        ) from error

    user = database.query(User).filter(User.email == email).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password reset link is invalid or expired",
        )
    if payload.get("credential") != password_fingerprint(user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password reset link is invalid or expired",
        )
    user.hashed_password = hash_password(data.new_password)
    database.commit()
    return ActionResponse(message="Password updated. You can now sign in.")


@router.get("/me", response_model=UserResponse)
def me(user: User = Depends(get_current_user)) -> UserResponse:
    return user_response(user)
