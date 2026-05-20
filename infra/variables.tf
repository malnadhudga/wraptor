variable "name" {
  description = "Name prefix for all resources (e.g. vespag)"
}

variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "email" {
  description = "Email address for failure alerts"
}

variable "ecr_image_uri" {
  description = "Full ECR image URI for the worker (e.g. 123456.dkr.ecr.us-east-1.amazonaws.com/vespag:latest)"
}

variable "instance_type" {
  description = "EC2 GPU instance type"
  default     = "g4dn.xlarge"
}

variable "max_instances" {
  description = "Maximum number of worker EC2 instances"
  default     = 3
}

variable "input_extension" {
  description = "Input file extension (e.g. .fasta, .csv)"
  default     = ".fasta"
}

variable "extra_env" {
  description = "Extra environment variables passed to the worker container (key=value pairs)"
  type        = map(string)
  default     = {}
}
