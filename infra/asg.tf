data "aws_ami" "deep_learning" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04) *"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  extra_env_flags = join(" ", [for k, v in var.extra_env : "-e ${k}=${v}"])

  user_data = <<-EOF
    #!/bin/bash
    set -e
    REGISTRY=$(echo "${var.ecr_image_uri}" | cut -d'/' -f1)
    aws ecr get-login-password --region ${var.region} | \
      docker login --username AWS --password-stdin $REGISTRY
    docker pull ${var.ecr_image_uri}
    docker run -d \
      --gpus all \
      --restart unless-stopped \
      --log-driver=awslogs \
      --log-opt awslogs-region=${var.region} \
      --log-opt awslogs-group=/wraptor/${var.name}/worker \
      --log-opt awslogs-create-group=true \
      -e SQS_QUEUE_URL=${aws_sqs_queue.jobs.url} \
      -e OUTPUT_BUCKET=${aws_s3_bucket.output.bucket} \
      -e INPUT_EXTENSION=${var.input_extension} \
      -e AWS_REGION=${var.region} \
      ${local.extra_env_flags} \
      ${var.ecr_image_uri}
  EOF
}

resource "aws_launch_template" "worker" {
  name          = "${var.name}-worker"
  image_id      = data.aws_ami.deep_learning.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_worker.arn
  }

  vpc_security_group_ids = [aws_security_group.worker.id]

  instance_market_options {
    market_type = "spot"
  }

  user_data = base64encode(local.user_data)

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.name}-worker" }
  }
}

resource "aws_autoscaling_group" "worker" {
  name                = "${var.name}-asg"
  min_size            = 0
  max_size            = var.max_instances
  desired_capacity    = 0
  vpc_zone_identifier = data.aws_subnets.default.ids
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-worker"
    propagate_at_launch = true
  }
}
