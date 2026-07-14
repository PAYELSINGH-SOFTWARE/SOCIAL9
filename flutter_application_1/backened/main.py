from fastapi import FastAPI
from router.auth import router as auth_router
from database import engine, Base
import models

Base.metadata.create_all(bind=engine)

app = FastAPI()

app.include_router(
    auth_router,
    prefix="/auth",
    tags=["Authentication"]
)