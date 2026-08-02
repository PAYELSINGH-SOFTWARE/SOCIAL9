"""vCueSocial9 backend package."""

from pathlib import Path

from dotenv import load_dotenv

# Load local development configuration before routers and the database module
# read environment variables. Existing process environment variables win.
load_dotenv(Path(__file__).resolve().parent.parent / ".env")