"""
Standalone Chronos inference script for Wraptor.

Input  : /tmp/input/data.csv  (columns: ts, <VALUE_COL>)
Output : /tmp/output/forecast.csv  (columns: ts, yhat)
"""

import os
import sys
import threading
import pandas as pd
import numpy as np

MODEL_ID      = os.environ["MODEL_ID"]           # e.g. amazon/chronos-t5-small or /weights/
BACKEND       = os.environ.get("CHRONOS_BACKEND", "chronos2")  # t5 or chronos2
DEVICE        = os.environ.get("DEVICE", "cuda")
HORIZON_STEPS = int(os.environ.get("HORIZON_STEPS", "96"))     # 96 × 15min = 24h
CONTEXT_STEPS = int(os.environ.get("CONTEXT_STEPS", "512"))
VALUE_COL     = os.environ.get("VALUE_COL", "value")           # generation_kw or consumption_kw

INPUT_PATH  = "/tmp/input/data.csv"
OUTPUT_PATH = "/tmp/output/forecast.csv"

_LOCK = threading.Lock()


def load_pipeline():
    if BACKEND == "chronos2":
        from chronos import Chronos2Pipeline
        pipeline = Chronos2Pipeline.from_pretrained(MODEL_ID)
        if DEVICE == "cuda":
            import torch
            if torch.cuda.is_available():
                pipeline.model.to("cuda")
    else:
        from chronos import ChronosPipeline
        pipeline = ChronosPipeline.from_pretrained(MODEL_ID)
        if DEVICE == "cuda":
            import torch
            if torch.cuda.is_available():
                pipeline.model.to("cuda")
    return pipeline


def median_quantile_index(pipeline) -> int:
    q = np.asarray(pipeline.quantiles, dtype=float)
    return int(np.argmin(np.abs(q - 0.5)))


def predict_chronos2(pipeline, ctx: np.ndarray, horizon: int) -> np.ndarray:
    ctx_len = min(len(ctx), CONTEXT_STEPS, pipeline.model_context_length)
    tail = ctx[-ctx_len:].astype(np.float32)
    with _LOCK:
        out = pipeline.predict(
            [tail],
            prediction_length=horizon,
            context_length=ctx_len,
            limit_prediction_length=False,
        )
    qi = median_quantile_index(pipeline)
    arr = out[0].detach().cpu().numpy() if hasattr(out[0], "detach") else np.asarray(out[0])
    return arr[0, qi, :].astype(float)


def predict_t5(pipeline, ctx: np.ndarray, horizon: int) -> np.ndarray:
    import torch
    CHUNK = 64
    parts, remaining = [], horizon
    while remaining > 0:
        h = min(CHUNK, remaining)
        tail = ctx[-CONTEXT_STEPS:].astype(np.float32)
        tensor = torch.tensor(tail, dtype=torch.float32)
        with _LOCK:
            samples = pipeline.predict(tensor, prediction_length=h, num_samples=20)
        arr = samples.detach().cpu().numpy() if hasattr(samples, "detach") else np.asarray(samples)
        chunk_y = arr[0].mean(axis=0).astype(float) if arr.ndim == 3 else arr.mean(axis=0).astype(float)
        parts.append(chunk_y)
        ctx = np.concatenate([ctx, chunk_y])
        remaining -= h
    return np.concatenate(parts)[:horizon]


def main():
    df = pd.read_csv(INPUT_PATH, parse_dates=["ts"])
    if VALUE_COL not in df.columns:
        print(f"ERROR: column '{VALUE_COL}' not found. Available: {list(df.columns)}", file=sys.stderr)
        sys.exit(1)

    df = df.sort_values("ts").reset_index(drop=True)
    ctx = pd.to_numeric(df[VALUE_COL], errors="coerce").tail(CONTEXT_STEPS).to_numpy(dtype=np.float64)

    if pd.isna(ctx).any():
        print("ERROR: context contains NaN values", file=sys.stderr)
        sys.exit(1)

    print(f"Loading Chronos ({BACKEND}) from {MODEL_ID} on {DEVICE}...")
    pipeline = load_pipeline()

    print(f"Running inference — horizon={HORIZON_STEPS} steps, context={len(ctx)} steps...")
    if BACKEND == "chronos2":
        yhat = predict_chronos2(pipeline, ctx, HORIZON_STEPS)
    else:
        yhat = predict_t5(pipeline, ctx, HORIZON_STEPS)

    last_ts = df["ts"].iloc[-1]
    future_ts = pd.date_range(
        start=last_ts + pd.Timedelta(minutes=15),
        periods=HORIZON_STEPS,
        freq="15min",
        tz="UTC",
    )
    result = pd.DataFrame({"ts": future_ts, "yhat": yhat})
    result.to_csv(OUTPUT_PATH, index=False)
    print(f"Done. Forecast written to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
