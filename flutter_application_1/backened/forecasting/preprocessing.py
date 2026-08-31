import pandas as pd


def prepare_data(records):
    """
    Convert Social9 engagement records into a clean time-series DataFrame.

    Expected input:
    [
        {
            "date": "2026-08-01",
            "engagement": 850
        },
        ...
    ]
    """

    if not records:
        raise ValueError("No forecasting data was provided.")

    df = pd.DataFrame(records)

    required_columns = {"date", "engagement"}

    if not required_columns.issubset(df.columns):
        raise ValueError(
            "Each record must contain 'date' and 'engagement'."
        )

    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    df["engagement"] = pd.to_numeric(
        df["engagement"],
        errors="coerce"
    )

    df = df.dropna(
        subset=["date", "engagement"]
    )

    if df.empty:
        raise ValueError("No valid forecasting records found.")

    # Combine duplicate dates
    df = (
        df.groupby("date", as_index=False)["engagement"]
        .sum()
    )

    # Sort chronologically
    df = df.sort_values("date")

    # Make daily frequency
    df = (
        df.set_index("date")
        .asfreq("D", fill_value=0)
        .reset_index()
    )

    if len(df) < 7:
        raise ValueError(
            "At least 7 days of historical data are required."
        )

    return df