data "archive_file" "scale_handler" {
  type        = "zip"
  source_file = "${path.module}/../lambda/scale_handler.py"
  output_path = "${path.module}/scale_handler.zip"
}

resource "aws_lambda_function" "scale_handler" {
  function_name    = "${var.name}-scale-handler"
  filename         = data.archive_file.scale_handler.output_path
  source_code_hash = data.archive_file.scale_handler.output_base64sha256
  handler          = "scale_handler.handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda.arn
  timeout          = 30

  environment {
    variables = {
      ASG_NAME      = aws_autoscaling_group.worker.name
      QUEUE_URL     = aws_sqs_queue.jobs.url
      MAX_INSTANCES = tostring(var.max_instances)
    }
  }
}

# ── Scale-out trigger ────────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "scale_out" {
  name = "${var.name}-scale-out-trigger"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = ["${var.name}-scale-out"]
      state     = { value = ["ALARM"] }
    }
  })
}

resource "aws_cloudwatch_event_target" "scale_out" {
  rule = aws_cloudwatch_event_rule.scale_out.name
  arn  = aws_lambda_function.scale_handler.arn
}

resource "aws_lambda_permission" "scale_out" {
  statement_id  = "AllowScaleOut"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scale_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scale_out.arn
}

# ── Scale-in trigger ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "scale_in" {
  name = "${var.name}-scale-in-trigger"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = ["${var.name}-scale-in"]
      state     = { value = ["ALARM"] }
    }
  })
}

resource "aws_cloudwatch_event_target" "scale_in" {
  rule = aws_cloudwatch_event_rule.scale_in.name
  arn  = aws_lambda_function.scale_handler.arn
}

resource "aws_lambda_permission" "scale_in" {
  statement_id  = "AllowScaleIn"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scale_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scale_in.arn
}
