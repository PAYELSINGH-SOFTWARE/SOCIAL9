"""Add provider-independent social account storage.

Revision ID: 20260825_03
Revises: 20260824_02
Create Date: 2026-08-25

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260825_03"
down_revision: Union[str, None] = "20260824_02"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_names = set(inspector.get_table_names())

    if "social_accounts" not in table_names:
        op.create_table(
            "social_accounts",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("provider", sa.String(length=30), nullable=False),
            sa.Column("provider_account_id", sa.String(length=255), nullable=False),
            sa.Column("account_name", sa.String(length=255), nullable=False),
            sa.Column("username", sa.String(length=255), nullable=True),
            sa.Column("status", sa.String(length=30), nullable=False),
            sa.Column("access_token_encrypted", sa.Text(), nullable=False),
            sa.Column("refresh_token_encrypted", sa.Text(), nullable=True),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("user_id", "provider", "provider_account_id", name="uq_social_account"),
        )
        op.create_index("ix_social_accounts_provider", "social_accounts", ["provider"])
        op.create_index("ix_social_accounts_user_id", "social_accounts", ["user_id"])
    else:
        columns = {
            column["name"] for column in inspector.get_columns("social_accounts")
        }
        required_legacy = {
            "id",
            "provider",
            "status",
            "access_token_encrypted",
        }
        if missing := required_legacy - columns:
            raise RuntimeError(
                "Existing social_accounts table is incompatible; "
                f"missing columns: {sorted(missing)}"
            )

        with op.batch_alter_table("social_accounts") as batch_op:
            if "user_id" not in columns:
                if "owner_id" not in columns:
                    raise RuntimeError("social_accounts needs owner_id or user_id")
                batch_op.alter_column("owner_id", new_column_name="user_id")
            if "provider_account_id" not in columns:
                if "external_account_id" not in columns:
                    raise RuntimeError(
                        "social_accounts needs external_account_id or provider_account_id"
                    )
                batch_op.alter_column(
                    "external_account_id", new_column_name="provider_account_id"
                )
            if "account_name" not in columns:
                if "display_name" not in columns:
                    raise RuntimeError(
                        "social_accounts needs display_name or account_name"
                    )
                batch_op.alter_column("display_name", new_column_name="account_name")
            if "expires_at" not in columns and "token_expires_at" in columns:
                batch_op.alter_column(
                    "token_expires_at", new_column_name="expires_at"
                )
            if "username" not in columns:
                batch_op.add_column(
                    sa.Column("username", sa.String(length=255), nullable=True)
                )
            if "created_at" not in columns:
                batch_op.add_column(
                    sa.Column(
                        "created_at",
                        sa.DateTime(timezone=True),
                        server_default=sa.func.now(),
                        nullable=False,
                    )
                )
            if "updated_at" not in columns:
                batch_op.add_column(
                    sa.Column(
                        "updated_at",
                        sa.DateTime(timezone=True),
                        server_default=sa.func.now(),
                        nullable=False,
                    )
                )

        inspector = sa.inspect(bind)
        indexes = {
            index["name"] for index in inspector.get_indexes("social_accounts")
        }
        if "ix_social_accounts_provider" not in indexes:
            op.create_index(
                "ix_social_accounts_provider", "social_accounts", ["provider"]
            )
        if "ix_social_accounts_user_id" not in indexes:
            op.create_index(
                "ix_social_accounts_user_id", "social_accounts", ["user_id"]
            )

        unique_column_sets = {
            tuple(constraint["column_names"])
            for constraint in inspector.get_unique_constraints("social_accounts")
        }
        target_unique = ("user_id", "provider", "provider_account_id")
        if target_unique not in unique_column_sets:
            duplicate = bind.execute(
                sa.text(
                    "SELECT 1 FROM social_accounts "
                    "GROUP BY user_id, provider, provider_account_id "
                    "HAVING COUNT(*) > 1 LIMIT 1"
                )
            ).first()
            if duplicate:
                raise RuntimeError(
                    "Duplicate social accounts must be resolved before migration"
                )
            with op.batch_alter_table("social_accounts") as batch_op:
                batch_op.create_unique_constraint(
                    "uq_social_account", list(target_unique)
                )

    if "oauth_states" not in table_names:
        op.create_table(
            "oauth_states",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("provider", sa.String(length=30), nullable=False),
            sa.Column("state_hash", sa.String(length=64), nullable=False),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index("ix_oauth_states_state_hash", "oauth_states", ["state_hash"], unique=True)
        op.create_index("ix_oauth_states_user_id", "oauth_states", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_oauth_states_user_id", table_name="oauth_states")
    op.drop_index("ix_oauth_states_state_hash", table_name="oauth_states")
    op.drop_table("oauth_states")
    op.drop_index("ix_social_accounts_user_id", table_name="social_accounts")
    op.drop_index("ix_social_accounts_provider", table_name="social_accounts")
    op.drop_table("social_accounts")
