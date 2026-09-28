"""Add website drafts and scheduled posts.

Revision ID: 20260825_04
Revises: 20260825_03
Create Date: 2026-08-25
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "20260825_04"
down_revision: Union[str, None] = "20260825_03"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "posts" in inspector.get_table_names():
        columns = {column["name"] for column in inspector.get_columns("posts")}
        required = {
            "id",
            "owner_id",
            "caption",
            "platforms",
            "status",
            "scheduled_for",
            "media_urls",
            "external_post_ids",
            "publish_error",
            "published_at",
            "created_at",
        }
        if missing := required - columns:
            raise RuntimeError(
                "Existing posts table is incompatible; "
                f"missing columns: {sorted(missing)}"
            )

        with op.batch_alter_table("posts") as batch_op:
            if "updated_at" not in columns:
                batch_op.add_column(
                    sa.Column(
                        "updated_at",
                        sa.DateTime(timezone=True),
                        server_default=sa.func.now(),
                        nullable=False,
                    )
                )
            batch_op.alter_column(
                "created_at",
                existing_type=sa.DateTime(timezone=True),
                server_default=sa.func.now(),
                existing_nullable=False,
            )

        inspector = sa.inspect(bind)
        indexes = {index["name"] for index in inspector.get_indexes("posts")}
        if "ix_posts_owner_id" not in indexes:
            op.create_index("ix_posts_owner_id", "posts", ["owner_id"])
        if "ix_posts_status" not in indexes:
            op.create_index("ix_posts_status", "posts", ["status"])
        return

    op.create_table(
        "posts",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("owner_id", sa.Integer(), nullable=False),
        sa.Column("caption", sa.Text(), nullable=False),
        sa.Column("platforms", sa.String(length=80), nullable=False),
        sa.Column("status", sa.String(length=30), nullable=False),
        sa.Column("scheduled_for", sa.DateTime(timezone=True), nullable=True),
        sa.Column("media_urls", sa.Text(), nullable=False),
        sa.Column("external_post_ids", sa.Text(), nullable=False),
        sa.Column("publish_error", sa.Text(), nullable=True),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["owner_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_posts_owner_id", "posts", ["owner_id"])
    op.create_index("ix_posts_status", "posts", ["status"])


def downgrade() -> None:
    op.drop_index("ix_posts_status", table_name="posts")
    op.drop_index("ix_posts_owner_id", table_name="posts")
    op.drop_table("posts")
