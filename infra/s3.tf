data "aws_caller_identity" "current" {}

# One bucket per repo holds everything Wraptor needs, split by prefix:
#   input/           job inputs uploaded by the client
#   output/{job_id}/ results written by the worker
#   build/           source.zip consumed by CodeBuild
locals {
  input_prefix  = "input"
  output_prefix = "output"
  build_prefix  = "build"
}

resource "aws_s3_bucket" "assets" {
  bucket        = "${var.name}-agentic-assets"
  force_destroy = true
}
