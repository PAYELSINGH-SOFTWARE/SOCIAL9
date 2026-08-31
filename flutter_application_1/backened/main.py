from fastapi import FastAPI

from .forecasting.router import router as forecasting_router
from .router.auth import router as auth_router

from .database import engine, Base

from . import models


# Create database tables
Base.metadata.create_all(bind=engine)


# Create FastAPI application
app = FastAPI(
    title="Social9 API"
)


# Authentication routes
app.include_router(
    auth_router,
    prefix="/auth",
    tags=["Authentication"]
)


# Forecasting routes
app.include_router(
    forecasting_router
)


@app.get("/")
def root():
    return {
        "message": "Social9 API is running"
    }