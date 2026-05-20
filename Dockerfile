FROM wraptor-base:latest

RUN pip3 install --no-cache-dir \
    chronos-forecasting>=1.3.0 \
    torch \
    transformers>=4.40.0 \
    accelerate>=0.30.0 \
    pandas>=2.0.0 \
    peft>=0.10.0

COPY predict.py /app/predict.py
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh
