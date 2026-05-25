import boto3
import json
import logging
import os
import shutil
import subprocess
import threading
from pathlib import Path

try:
    import urllib.request as _urllib
except ImportError:
    _urllib = None

METADATA_URL = "http://169.254.169.254/latest/meta-data/spot/interruption-notice"

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

QUEUE_URL       = os.environ['SQS_QUEUE_URL']
OUTPUT_BUCKET   = os.environ['OUTPUT_BUCKET']
INPUT_EXTENSION = os.environ.get('INPUT_EXTENSION', '.fasta')
AWS_REGION      = os.environ['AWS_REGION']

VISIBILITY_TIMEOUT = 600  # 10 min
HEARTBEAT_INTERVAL = 480  # 8 min — extend before timeout

INPUT_DIR  = Path('/tmp/input')
OUTPUT_DIR = Path('/tmp/output')

sqs = boto3.client('sqs', region_name=AWS_REGION)
s3  = boto3.client('s3',  region_name=AWS_REGION)


def cleanup():
    shutil.rmtree(INPUT_DIR,  ignore_errors=True)
    shutil.rmtree(OUTPUT_DIR, ignore_errors=True)
    INPUT_DIR.mkdir(parents=True)
    OUTPUT_DIR.mkdir(parents=True)


def spot_watcher(job_id: str, receipt_handle: str, stop_event: threading.Event):
    while not stop_event.wait(5):
        try:
            req = _urllib.urlopen(METADATA_URL, timeout=1)
            if req.status == 200:
                logger.warning(f"[SPOT_INTERRUPTED] job_id={job_id} instance reclaimed by AWS")
                # release message immediately so another instance retries without waiting for visibility timeout
                sqs.change_message_visibility(
                    QueueUrl=QUEUE_URL,
                    ReceiptHandle=receipt_handle,
                    VisibilityTimeout=0,
                )
                break
        except Exception:
            pass


def heartbeat(receipt_handle: str, stop_event: threading.Event):
    while not stop_event.wait(HEARTBEAT_INTERVAL):
        try:
            sqs.change_message_visibility(
                QueueUrl=QUEUE_URL,
                ReceiptHandle=receipt_handle,
                VisibilityTimeout=VISIBILITY_TIMEOUT,
            )
            logger.info("Visibility timeout extended")
        except Exception as exc:
            logger.warning(f"Heartbeat failed: {exc}")


def download_input(s3_path: str):
    bucket, key = s3_path.replace('s3://', '').split('/', 1)
    dest = INPUT_DIR / f"data{INPUT_EXTENSION}"
    s3.download_file(bucket, key, str(dest))
    logger.info(f"Downloaded {s3_path} → {dest}")


def upload_output(job_id: str):
    files = list(OUTPUT_DIR.glob('*'))
    if not files:
        raise RuntimeError("run.sh produced no output files")
    for f in files:
        key = f"{job_id}/{f.name}"
        s3.upload_file(str(f), OUTPUT_BUCKET, key)
        logger.info(f"Uploaded → s3://{OUTPUT_BUCKET}/{key}")


def process(message: dict):
    body          = json.loads(message['Body'].lstrip('\ufeff'))
    job_id        = body['job_id']
    input_s3_path = body['input_s3_path']
    receipt_handle = message['ReceiptHandle']

    logger.info(f"[{job_id}] Starting")
    cleanup()

    stop_event = threading.Event()
    threading.Thread(target=heartbeat, args=(receipt_handle, stop_event), daemon=True).start()
    threading.Thread(target=spot_watcher, args=(job_id, receipt_handle, stop_event), daemon=True).start()

    try:
        download_input(input_s3_path)

        result = subprocess.run(
            ['bash', '/app/run.sh'],
            capture_output=True,
            text=True,
        )
        if result.stdout:
            logger.info(f"[{job_id}] stdout: {result.stdout.strip()}")
        if result.stderr:
            logger.warning(f"[{job_id}] stderr: {result.stderr.strip()}")
        if result.returncode != 0:
            raise RuntimeError(f"run.sh exited with code {result.returncode}")

        upload_output(job_id)
        sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)
        logger.info(f"[{job_id}] Done")

    except Exception as exc:
        logger.error(f"[{job_id}] Failed: {exc}")
        # message not deleted — SQS will retry up to maxReceiveCount then DLQ

    finally:
        stop_event.set()


def main():
    logger.info("Wraptor worker starting")
    while True:
        resp = sqs.receive_message(
            QueueUrl=QUEUE_URL,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=20,
            VisibilityTimeout=VISIBILITY_TIMEOUT,
        )
        messages = resp.get('Messages', [])
        if messages:
            process(messages[0])


if __name__ == '__main__':
    main()
