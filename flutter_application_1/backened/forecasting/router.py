from typing import List

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from .service import forecasting_service


router = APIRouter(
    prefix="/forecasting",
    tags=["Forecasting"]
)


class EngagementRecord(BaseModel):
    date: str
    engagement: float = Field(
        ge=0
    )


class ForecastRequest(BaseModel):
    records: List[EngagementRecord]

    periods: int = Field(
        default=7,
        ge=1,
        le=90
    )

    model: str = "auto"


@router.get("/health")
def forecasting_health():
    return {
        "status": "ok",
        "service": "Social9 Forecasting",
        "models": [
            "baseline",
            "moving_average",
            "holt",
            "previous_cycle",
            "arima",
            "prophet"
        ]
    }


@router.post("/forecast")
def create_forecast(
    request: ForecastRequest
):
    try:

        records = [
            {
                "date": record.date,
                "engagement": record.engagement
            }
            for record in request.records
        ]

        result = forecasting_service.forecast(
            records=records,
            periods=request.periods,
            model_name=request.model
        )

        return result

    except ValueError as error:

        raise HTTPException(
            status_code=400,
            detail=str(error)
        )

    except Exception as error:

        raise HTTPException(
            status_code=500,
            detail=f"Forecasting failed: {str(error)}"
        )