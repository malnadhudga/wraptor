# The ECR repo is created by deploy.sh (via the AWS CLI) before the CodeBuild
# build runs. Terraform does not manage it to avoid chicken-and-egg ordering:
# the repo must exist before CodeBuild pushes the image and before the ASG
# launches instances that pull it.
