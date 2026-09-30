"""Add user email verification state.

Revision ID: 20260824_02
Revises: 20260824_01
Create Date: 2026-08-24

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260824_02"
down_revision: Union[str, None] = "20260824_01"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    if "is_verified" in {
        column["name"] for column in inspector.get_columns("users")
    }:
        return

    with op.batch_alter_table("users") as batch_op:
        batch_op.add_column(
            sa.Column(
                "is_verified",
                sa.Boolean(),
                server_default=sa.true(),
                nullable=False,
            )
        )


def downgrade() -> None:
    with op.batch_alter_table("users") as batch_op:
        batch_op.drop_column("is_verified")
