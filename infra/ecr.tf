resource "aws_ecr_repository" "worker" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"
}
