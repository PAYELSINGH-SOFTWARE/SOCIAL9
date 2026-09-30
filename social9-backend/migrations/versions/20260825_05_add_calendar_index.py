"""Optimize owner calendar range queries.

Revision ID: 20260825_05
Revises: 20260825_04
Create Date: 2026-08-25
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "20260825_05"
down_revision: Union[str, None] = "20260825_04"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    indexes = {
        index["name"]
        for index in sa.inspect(op.get_bind()).get_indexes("posts")
    }
    if "ix_posts_owner_scheduled" not in indexes:
        op.create_index(
            "ix_posts_owner_scheduled", "posts", ["owner_id", "scheduled_for"]
        )


def downgrade() -> None:
    op.drop_index("ix_posts_owner_scheduled", table_name="posts")
