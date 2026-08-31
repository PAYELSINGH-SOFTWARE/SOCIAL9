import numpy as np
import pandas as pd

from .preprocessing import prepare_data

from .models import (
    baseline_forecast,
    moving_average_forecast,
    holt_forecast,
    previous_cycle_forecast,
    arima_forecast,
    prophet_forecast,
)


class ForecastingService:

    def _evaluate_model(
        self,
        actual,
        predicted
    ):
        """
        Calculate Mean Absolute Error.
        """

        actual = np.asarray(
            actual,
            dtype=float
        )

        predicted = np.asarray(
            predicted,
            dtype=float
        )

        return float(
            np.mean(
                np.abs(
                    actual - predicted
                )
            )
        )

    def _select_best_model(
        self,
        df
    ):
        """
        Compare forecasting models using
        a holdout validation period.
        """

        series = df["engagement"]

        # Use the last 20% or at least 3 observations
        validation_size = max(
            3,
            min(
                7,
                len(series) // 5
            )
        )

        if len(series) <= validation_size + 3:
            validation_size = 3

        train = series.iloc[
            :-validation_size
        ]

        actual = series.iloc[
            -validation_size:
        ]

        scores = {}

        models = {}

        # Baseline
        try:
            prediction = baseline_forecast(
                train,
                validation_size
            )

            scores["baseline"] = self._evaluate_model(
                actual,
                prediction
            )

            models["baseline"] = baseline_forecast

        except Exception:
            pass

        # Moving Average
        try:
            prediction = moving_average_forecast(
                train,
                validation_size
            )

            scores["moving_average"] = self._evaluate_model(
                actual,
                prediction
            )

            models["moving_average"] = moving_average_forecast

        except Exception:
            pass

        # Holt
        try:
            prediction = holt_forecast(
                train,
                validation_size
            )

            scores["holt"] = self._evaluate_model(
                actual,
                prediction
            )

            models["holt"] = holt_forecast

        except Exception:
            pass

        # Previous Cycle
        try:
            prediction = previous_cycle_forecast(
                train,
                validation_size
            )

            scores["previous_cycle"] = self._evaluate_model(
                actual,
                prediction
            )

            models["previous_cycle"] = previous_cycle_forecast

        except Exception:
            pass

        # ARIMA
        try:
            prediction = arima_forecast(
                train,
                validation_size
            )

            scores["arima"] = self._evaluate_model(
                actual,
                prediction
            )

            models["arima"] = arima_forecast

        except Exception:
            pass

        # Prophet
        try:
            train_df = df.iloc[
                :-validation_size
            ]

            prediction = prophet_forecast(
                train_df,
                validation_size
            )

            scores["prophet"] = self._evaluate_model(
                actual,
                prediction
            )

            models["prophet"] = prophet_forecast

        except Exception:
            pass

        if not scores:
            raise RuntimeError(
                "No forecasting model could be trained."
            )

        best_model = min(
            scores,
            key=scores.get
        )

        return (
            best_model,
            scores,
            models
        )

    def _recommendation(
        self,
        predictions,
        dates
    ):
        """
        Recommend the best future day
        based on predicted engagement.
        """

        best_index = int(
            np.argmax(predictions)
        )

        best_date = dates[best_index]

        timestamp = pd.Timestamp(
            best_date
        )

        return {
            "best_day": timestamp.strftime(
                "%A"
            ),
            "best_date": timestamp.strftime(
                "%Y-%m-%d"
            ),
            "best_time": "Best posting time requires "
                         "hour-level historical data."
        }

    def forecast(
        self,
        records,
        periods=7,
        model_name="auto"
    ):
        """
        Main forecasting function.
        """

        if periods < 1 or periods > 90:
            raise ValueError(
                "Forecast periods must be between 1 and 90."
            )

        df = prepare_data(
            records
        )

        if model_name == "auto":

            (
                selected_model,
                scores,
                models
            ) = self._select_best_model(df)

        else:

            allowed_models = {
                "baseline",
                "moving_average",
                "holt",
                "previous_cycle",
                "arima",
                "prophet",
            }

            if model_name not in allowed_models:
                raise ValueError(
                    f"Unsupported model: {model_name}"
                )

            selected_model = model_name

            scores = {}

            models = {
                "baseline": baseline_forecast,
                "moving_average": moving_average_forecast,
                "holt": holt_forecast,
                "previous_cycle": previous_cycle_forecast,
                "arima": arima_forecast,
                "prophet": prophet_forecast,
            }

        # Train selected model on all historical data
        if selected_model == "prophet":

            predictions = prophet_forecast(
                df,
                periods
            )

        elif selected_model == "moving_average":

            predictions = moving_average_forecast(
                df["engagement"],
                periods
            )

        elif selected_model == "previous_cycle":

            predictions = previous_cycle_forecast(
                df["engagement"],
                periods
            )

        elif selected_model == "holt":

            predictions = holt_forecast(
                df["engagement"],
                periods
            )

        elif selected_model == "arima":

            predictions = arima_forecast(
                df["engagement"],
                periods
            )

        else:

            predictions = baseline_forecast(
                df["engagement"],
                periods
            )

        future_dates = pd.date_range(
            start=df["date"].max()
            + pd.Timedelta(days=1),
            periods=periods,
            freq="D"
        )

        prediction_list = []

        for date, prediction in zip(
            future_dates,
            predictions
        ):
            prediction_list.append(
                {
                    "date": date.strftime(
                        "%Y-%m-%d"
                    ),
                    "predicted_engagement": round(
                        float(prediction),
                        2
                    )
                }
            )

        recommendation = self._recommendation(
            predictions,
            future_dates
        )

        return {
            "model": selected_model,
            "historical_days": len(df),
            "forecast_days": periods,
            "model_scores": {
                key: round(
                    value,
                    2
                )
                for key, value in scores.items()
            },
            "predictions": prediction_list,
            "recommendation": recommendation
        }


forecasting_service = ForecastingService()