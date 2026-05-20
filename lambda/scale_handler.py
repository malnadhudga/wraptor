import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

asg = boto3.client('autoscaling')
sqs = boto3.client('sqs')

ASG_NAME      = os.environ['ASG_NAME']
QUEUE_URL     = os.environ['QUEUE_URL']
MAX_INSTANCES = int(os.environ.get('MAX_INSTANCES', 3))


def queue_stats():
    resp = sqs.get_queue_attributes(
        QueueUrl=QUEUE_URL,
        AttributeNames=[
            'ApproximateNumberOfMessages',
            'ApproximateNumberOfMessagesNotVisible',
        ],
    )
    visible   = int(resp['Attributes']['ApproximateNumberOfMessages'])
    in_flight = int(resp['Attributes']['ApproximateNumberOfMessagesNotVisible'])
    return visible, in_flight


def desired_for(visible: int, in_flight: int) -> int:
    total = visible + in_flight
    if total == 0:
        return 0
    if total <= 2:
        return 1
    if total <= 4:
        return 2
    return min(total, MAX_INSTANCES)


def set_capacity(desired: int):
    resp = asg.describe_auto_scaling_groups(AutoScalingGroupNames=[ASG_NAME])
    current = resp['AutoScalingGroups'][0]['DesiredCapacity']
    if desired == current:
        logger.info(f"No change needed (desired={desired})")
        return
    asg.set_desired_capacity(
        AutoScalingGroupName=ASG_NAME,
        DesiredCapacity=desired,
        HonorCooldown=False,
    )
    logger.info(f"Scaled {ASG_NAME}: {current} → {desired}")


def handler(event, context):
    alarm_name = event.get('detail', {}).get('alarmName', '')
    visible, in_flight = queue_stats()
    logger.info(f"Queue — visible={visible}, in_flight={in_flight}, alarm={alarm_name}")

    if 'scale-in' in alarm_name:
        if visible == 0 and in_flight == 0:
            set_capacity(0)
        else:
            logger.info("Scale-in skipped: jobs still active")
    else:
        set_capacity(desired_for(visible, in_flight))
