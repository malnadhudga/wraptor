FROM wraptor-base:latest

# CPU-only PyTorch — much smaller than CUDA build
RUN pip3 install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

RUN pip3 install --no-cache-dir \
    chronos-forecasting \
    transformers \
    accelerate \
    pandas

COPY predict.py /app/predict.py
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh
