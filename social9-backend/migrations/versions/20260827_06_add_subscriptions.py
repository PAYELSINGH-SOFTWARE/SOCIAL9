"""Add provider-neutral subscriptions and paid feature entitlements.

Revision ID: 20260827_06
Revises: 20260825_05
Create Date: 2026-08-27
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "20260827_06"
down_revision: Union[str, None] = "20260825_05"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "subscriptions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("provider", sa.String(length=30), nullable=True),
        sa.Column("provider_customer_id", sa.String(length=255), nullable=True),
        sa.Column("provider_subscription_id", sa.String(length=255), nullable=True),
        sa.Column("plan", sa.String(length=30), nullable=False, server_default="free"),
        sa.Column("status", sa.String(length=30), nullable=False, server_default="inactive"),
        sa.Column("current_period_end", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "cancel_at_period_end", sa.Boolean(), nullable=False, server_default=sa.false()
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "provider", "provider_subscription_id", name="uq_subscriptions_provider_id"
        ),
        sa.UniqueConstraint("user_id", name="uq_subscriptions_user"),
    )
    op.create_index("ix_subscriptions_user_id", "subscriptions", ["user_id"])
    op.create_index("ix_subscriptions_status", "subscriptions", ["status"])


def downgrade() -> None:
    op.drop_index("ix_subscriptions_status", table_name="subscriptions")
    op.drop_index("ix_subscriptions_user_id", table_name="subscriptions")
    op.drop_table("subscriptions")
