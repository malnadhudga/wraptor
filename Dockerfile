FROM wraptor-base:latest

RUN pip3 install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu \
 && pip3 install --no-cache-dir chronos-forecasting transformers pandas

COPY predict.py /app/predict.py
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh
