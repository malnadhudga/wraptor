output "sqs_queue_url" {
  value = aws_sqs_queue.jobs.url
}

output "input_bucket_name" {
  value = aws_s3_bucket.input.bucket
}

output "output_bucket_name" {
  value = aws_s3_bucket.output.bucket
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "ecr_repository_url" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.name}"
}

output "build_source_bucket" {
  value = aws_s3_bucket.build_source.bucket
}

output "codebuild_project" {
  value = aws_codebuild_project.builder.name
}
