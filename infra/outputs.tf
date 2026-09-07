output "sqs_queue_url" {
  value = aws_sqs_queue.jobs.url
}

output "assets_bucket_name" {
  value = aws_s3_bucket.assets.bucket
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "ecr_repository_url" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.name}"
}

output "codebuild_project" {
  value = aws_codebuild_project.builder.name
}
