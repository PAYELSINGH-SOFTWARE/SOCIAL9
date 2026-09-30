"""Print a data-free database schema inventory for deployment diagnostics."""

from __future__ import annotations

import json

from sqlalchemy import inspect, text

from app.database import engine


def main() -> None:
    with engine.connect() as connection:
        inspector = inspect(connection)
        tables: dict[str, object] = {}
        table_names = sorted(inspector.get_table_names())

        for table_name in table_names:
            tables[table_name] = {
                "columns": [
                    {
                        "name": column["name"],
                        "type": str(column["type"]),
                        "nullable": column["nullable"],
                        "default": column.get("default"),
                    }
                    for column in inspector.get_columns(table_name)
                ],
                "indexes": [
                    {
                        "name": index["name"],
                        "columns": index["column_names"],
                        "unique": index["unique"],
                    }
                    for index in inspector.get_indexes(table_name)
                ],
            }

        alembic_revision = None
        if "alembic_version" in table_names:
            alembic_revision = connection.execute(
                text("SELECT version_num FROM alembic_version LIMIT 1")
            ).scalar_one_or_none()

        print(
            "SOCIAL9_SCHEMA_SNAPSHOT="
            + json.dumps(
                {
                    "alembic_revision": alembic_revision,
                    "tables": tables,
                },
                sort_keys=True,
            )
        )


if __name__ == "__main__":
    main()
