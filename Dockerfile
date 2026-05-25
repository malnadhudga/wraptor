FROM 119492371915.dkr.ecr.us-east-1.amazonaws.com/boltz2:latest

COPY wrapper/requirements.txt /tmp/wraptor-req.txt
RUN pip3 install --no-cache-dir -r /tmp/wraptor-req.txt

WORKDIR /app
COPY wrapper/worker.py .
COPY run.sh .
RUN chmod +x run.sh

CMD ["python3", "worker.py"]
