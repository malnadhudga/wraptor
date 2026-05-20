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
  gpu_instances = ["g4dn.xlarge", "g4dn.2xlarge", "g5.xlarge"]
  cpu_instances = ["c5.2xlarge", "m5.2xlarge", "c6i.2xlarge"]
  instance_types = var.use_gpu ? local.gpu_instances : local.cpu_instances
  gpu_flag       = var.use_gpu ? "--gpus all" : ""

  user_data = <<-EOF
    #!/bin/bash
    set -e
    REGISTRY=$(echo "${var.ecr_image_uri}" | cut -d'/' -f1)
    aws ecr get-login-password --region ${var.region} | \
      docker login --username AWS --password-stdin $REGISTRY
    docker pull ${var.ecr_image_uri}
    docker run -d ${local.gpu_flag} \
      --restart unless-stopped \
      --log-driver=awslogs \
      --log-opt awslogs-region=${var.region} \
      --log-opt awslogs-group=/wraptor/${var.name}/worker \
      --log-opt awslogs-create-group=true \
      -e SQS_QUEUE_URL=${aws_sqs_queue.jobs.url} \
      -e OUTPUT_BUCKET=${aws_s3_bucket.output.bucket} \
      -e INPUT_EXTENSION=${var.input_extension} \
      -e AWS_REGION=${var.region} \
      ${var.ecr_image_uri}
  EOF
}

resource "aws_launch_template" "worker" {
  name     = "${var.name}-worker"
  image_id = data.aws_ami.deep_learning.id

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_worker.arn
  }

  vpc_security_group_ids = [aws_security_group.worker.id]

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

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.worker.id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = local.instance_types
        content {
          instance_type = override.value
        }
      }
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-worker"
    propagate_at_launch = true
  }
}
