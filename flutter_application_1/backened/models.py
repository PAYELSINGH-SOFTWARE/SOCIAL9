from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import relationship
from .database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    posts = relationship("Post", back_populates="owner", cascade="all, delete-orphan")
    social_accounts = relationship("SocialAccount", back_populates="owner", cascade="all, delete-orphan")


class Post(Base):
    __tablename__ = "posts"

    id = Column(Integer, primary_key=True, index=True)
    caption = Column(Text, nullable=False)
    media_urls = Column(Text, nullable=False, default="[]")
    external_post_ids = Column(Text, nullable=False, default="{}")
    publish_error = Column(Text, nullable=True)
    published_at = Column(DateTime(timezone=True), nullable=True)
    platforms = Column(String, nullable=False)
    status = Column(String, nullable=False, default="draft")
    scheduled_for = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    owner = relationship("User", back_populates="posts")


class SocialAccount(Base):
    __tablename__ = "social_accounts"

    id = Column(Integer, primary_key=True, index=True)
    provider = Column(String, nullable=False)
    external_account_id = Column(String, nullable=False)
    display_name = Column(String, nullable=False)
    status = Column(String, nullable=False, default="connected")
    access_token_encrypted = Column(Text, nullable=False)
    refresh_token_encrypted = Column(Text, nullable=True)
    token_expires_at = Column(DateTime(timezone=True), nullable=True)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    owner = relationship("User", back_populates="social_accounts")

class SocialLoginAttempt(Base):
    __tablename__ = "social_login_attempts"

    id = Column(String, primary_key=True)
    provider = Column(String, nullable=False)
    status = Column(String, nullable=False, default="pending")
    app_token_encrypted = Column(Text, nullable=True)
    error_message = Column(String, nullable=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
