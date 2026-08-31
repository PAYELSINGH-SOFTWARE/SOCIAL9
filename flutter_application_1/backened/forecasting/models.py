import numpy as np
import pandas as pd

from statsmodels.tsa.arima.model import ARIMA
from statsmodels.tsa.holtwinters import Holt
from prophet import Prophet


def baseline_forecast(series, periods):
    """
    Last Observed Value baseline.
    """

    last_value = float(series.iloc[-1])

    return np.repeat(
        max(0, last_value),
        periods
    )


def moving_average_forecast(
    series,
    periods,
    window=7
):
    """
    Moving Average forecasting.
    """

    window = min(window, len(series))

    average = float(
        series.tail(window).mean()
    )

    return np.repeat(
        max(0, average),
        periods
    )


def holt_forecast(series, periods):
    """
    Holt's Linear Trend forecasting.
    """

    model = Holt(
        series.astype(float),
        initialization_method="estimated"
    )

    fitted = model.fit(
        optimized=True
    )

    forecast = fitted.forecast(periods)

    return np.maximum(
        np.asarray(forecast, dtype=float),
        0
    )


def previous_cycle_forecast(
    series,
    periods,
    cycle=7
):
    """
    Repeat the previous weekly cycle.
    """

    if len(series) < cycle:
        return moving_average_forecast(
            series,
            periods,
            window=len(series)
        )

    last_cycle = np.asarray(
        series.tail(cycle),
        dtype=float
    )

    repetitions = int(
        np.ceil(periods / cycle)
    )

    forecast = np.tile(
        last_cycle,
        repetitions
    )

    return np.maximum(
        forecast[:periods],
        0
    )


def arima_forecast(series, periods):
    """
    ARIMA time-series forecasting.
    """

    model = ARIMA(
        series.astype(float),
        order=(1, 1, 1)
    )

    fitted = model.fit()

    forecast = fitted.forecast(
        steps=periods
    )

    return np.maximum(
        np.asarray(forecast, dtype=float),
        0
    )


def prophet_forecast(df, periods):
    """
    Facebook Prophet forecasting.
    """

    prophet_df = df[
        ["date", "engagement"]
    ].rename(
        columns={
            "date": "ds",
            "engagement": "y"
        }
    )

    model = Prophet(
        daily_seasonality=False,
        weekly_seasonality=True,
        yearly_seasonality=False
    )

    model.fit(prophet_df)

    future = model.make_future_dataframe(
        periods=periods,
        freq="D"
    )

    forecast = model.predict(future)

    predictions = forecast[
        "yhat"
    ].tail(periods).to_numpy()

    return np.maximum(
        predictions,
        0
    )