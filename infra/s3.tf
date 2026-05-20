data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "input" {
  bucket = "${var.name}-input-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "output" {
  bucket = "${var.name}-output-${data.aws_caller_identity.current.account_id}"
}
