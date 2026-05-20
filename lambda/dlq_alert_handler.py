import boto3
import json
import logging
import os
import urllib.parse

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns    = boto3.client('sns')
logs   = boto3.client('logs')

SNS_TOPIC_ARN   = os.environ['SNS_TOPIC_ARN']
LOG_GROUP       = os.environ['LOG_GROUP']
AWS_REGION      = os.environ['WRAPTOR_REGION']
WRAPTOR_NAME    = os.environ['WRAPTOR_NAME']


def _get_error_line(job_id: str) -> str:
    try:
        resp = logs.filter_log_events(
            logGroupName=LOG_GROUP,
            filterPattern=f'"{job_id}" "Failed"',
            limit=1,
        )
        events = resp.get('events', [])
        if events:
            return events[0]['message'].strip()
    except Exception as e:
        logger.warning(f"Could not fetch log error: {e}")
    return "See CloudWatch logs for details"


def _cloudwatch_link(job_id: str) -> str:
    filter_pattern = urllib.parse.quote(f'"{job_id}"', safe='')
    log_group_encoded = urllib.parse.quote(LOG_GROUP, safe='')
    return (
        f"https://{AWS_REGION}.console.aws.amazon.com/cloudwatch/home"
        f"?region={AWS_REGION}#logsV2:log-groups/log-group"
        f"/{log_group_encoded}/log-events"
        f"$3FfilterPattern$3D{filter_pattern}"
    )


def handler(event, context):
    for record in event.get('Records', []):
        try:
            body = json.loads(record['body'])
            job_id        = body.get('job_id', 'unknown')
            input_s3_path = body.get('input_s3_path', 'unknown')

            error_line  = _get_error_line(job_id)
            cw_link     = _cloudwatch_link(job_id)

            subject = f"Inference Failed - {job_id}"
            message = (
                f"An inference job failed after 3 attempts.\n\n"
                f"Job ID  : {job_id}\n"
                f"Input   : {input_s3_path}\n"
                f"Error   : {error_line}\n\n"
                f"CloudWatch Logs:\n  {cw_link}\n"
            )

            sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject, Message=message)
            logger.info(f"Failure alert sent for job_id={job_id}")

        except Exception as e:
            logger.error(f"Failed to process DLQ record: {e}")
