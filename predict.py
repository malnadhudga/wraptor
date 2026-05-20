"""
Chronos generation forecasting for Wraptor.

Input  : /tmp/input/data.csv  — columns: ts, generation_kw
Output : /tmp/output/forecast.csv — columns: ts, yhat
"""

import os
import sys
import pandas as pd
import numpy as np

MODEL_ID      = os.environ.get("MODEL_ID", "amazon/chronos-t5-tiny")
HORIZON_STEPS = int(os.environ.get("HORIZON_STEPS", "96"))   # 96 × 15min = 24h
CONTEXT_STEPS = int(os.environ.get("CONTEXT_STEPS", "512"))
VALUE_COL     = "generation_kw"

INPUT_PATH  = "/tmp/input/data.csv"
OUTPUT_PATH = "/tmp/output/forecast.csv"


def main():
    df = pd.read_csv(INPUT_PATH, parse_dates=["ts"])
    if VALUE_COL not in df.columns:
        print(f"ERROR: column '{VALUE_COL}' not found. Got: {list(df.columns)}", file=sys.stderr)
        sys.exit(1)

    df = df.sort_values("ts").reset_index(drop=True)
    ctx = pd.to_numeric(df[VALUE_COL], errors="coerce").tail(CONTEXT_STEPS).to_numpy(dtype=np.float64)

    if pd.isna(ctx).any():
        print("ERROR: context contains NaN values", file=sys.stderr)
        sys.exit(1)

    print(f"Loading {MODEL_ID} on CPU...")
    from chronos import ChronosPipeline
    import torch

    pipeline = ChronosPipeline.from_pretrained(MODEL_ID, device_map="cpu", torch_dtype=torch.float32)

    print(f"Running inference — horizon={HORIZON_STEPS} steps, context={len(ctx)} steps...")
    CHUNK = 64
    parts, remaining, rolling_ctx = [], HORIZON_STEPS, ctx.copy()

    while remaining > 0:
        h = min(CHUNK, remaining)
        tail = rolling_ctx[-CONTEXT_STEPS:].astype(np.float32)
        tensor = torch.tensor(tail, dtype=torch.float32)
        samples = pipeline.predict(tensor, prediction_length=h, num_samples=20)
        arr = samples.detach().cpu().numpy()
        chunk_y = arr[0].mean(axis=0).astype(float) if arr.ndim == 3 else arr.mean(axis=0).astype(float)
        parts.append(chunk_y)
        rolling_ctx = np.concatenate([rolling_ctx, chunk_y])
        remaining -= h

    yhat = np.concatenate(parts)[:HORIZON_STEPS]

    last_ts = df["ts"].iloc[-1]
    future_ts = pd.date_range(
        start=last_ts + pd.Timedelta(minutes=15),
        periods=HORIZON_STEPS,
        freq="15min",
        tz="UTC",
    )

    pd.DataFrame({"ts": future_ts, "yhat": yhat}).to_csv(OUTPUT_PATH, index=False)
    print(f"Done. Written to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
