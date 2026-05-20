resource "aws_cloudwatch_log_group" "worker" {
  name              = "/wraptor/${var.name}/worker"
  retention_in_days = 30
}

resource "aws_cloudwatch_metric_alarm" "scale_out" {
  alarm_name          = "${var.name}-scale-out"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Jobs waiting in queue — scale out"

  dimensions = {
    QueueName = aws_sqs_queue.jobs.name
  }
}

resource "aws_cloudwatch_metric_alarm" "scale_in" {
  alarm_name          = "${var.name}-scale-in"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 10 # 10 × 60s = 10 min idle
  threshold           = 0
  alarm_description   = "Queue empty and no jobs in-flight — scale in"

  metric_query {
    id          = "total"
    expression  = "visible + inflight"
    label       = "Total Messages"
    return_data = true
  }

  metric_query {
    id = "visible"
    metric {
      metric_name = "ApproximateNumberOfMessagesVisible"
      namespace   = "AWS/SQS"
      period      = 60
      stat        = "Sum"
      dimensions = {
        QueueName = aws_sqs_queue.jobs.name
      }
    }
  }

  metric_query {
    id = "inflight"
    metric {
      metric_name = "ApproximateNumberOfMessagesNotVisible"
      namespace   = "AWS/SQS"
      period      = 60
      stat        = "Sum"
      dimensions = {
        QueueName = aws_sqs_queue.jobs.name
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "dlq_alert" {
  alarm_name          = "${var.name}-dlq-alert"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Job permanently failed — check DLQ"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}
