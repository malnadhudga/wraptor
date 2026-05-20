FROM wraptor-base:latest

# Install your model's dependencies here
RUN pip3 install --no-cache-dir vespag

COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh
