#!/bin/bash
set -e

NAME=$1
EMAIL=$2
REGION=${3:-us-east-1}
INPUT_EXTENSION=$4

if [ -z "$NAME" ] || [ -z "$EMAIL" ] || [ -z "$INPUT_EXTENSION" ]; then
  echo "Usage: ./deploy.sh <name> <email> [region] <input_extension>"
  echo "Example: ./deploy.sh vespag user@example.com us-east-1 .csv"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
ECR_IMAGE_URI="$ECR_REGISTRY/$NAME:latest"

echo "Deploying Wraptor: $NAME ($REGION)"

# 1. Create ECR repo (skip if exists)
aws ecr create-repository --repository-name "$NAME" --region "$REGION" 2>/dev/null || true

cd infra/
terraform init -upgrade

# 2. Provision the build infrastructure (CodeBuild project + assets bucket) first
echo "Provisioning build infrastructure..."
terraform apply \
  -target=aws_s3_bucket.assets \
  -target=aws_iam_role.codebuild \
  -target=aws_iam_role_policy.codebuild \
  -target=aws_codebuild_project.builder \
  -var="name=$NAME" \
  -var="region=$REGION" \
  -var="email=$EMAIL" \
  -var="ecr_image_uri=$ECR_IMAGE_URI" \
  -var="input_extension=$INPUT_EXTENSION" \
  -auto-approve

ASSETS_BUCKET=$(terraform output -raw assets_bucket_name)
CODEBUILD_PROJECT=$(terraform output -raw codebuild_project)
cd ..

# 3. Build and push the image with AWS CodeBuild
./build_image.sh "$NAME" "$REGION" "$ASSETS_BUCKET" "$CODEBUILD_PROJECT" "$ECR_REGISTRY" "$ECR_IMAGE_URI"

# 4. Provision the rest of the infrastructure
cd infra/
terraform apply \
  -var="name=$NAME" \
  -var="region=$REGION" \
  -var="email=$EMAIL" \
  -var="ecr_image_uri=$ECR_IMAGE_URI" \
  -var="input_extension=$INPUT_EXTENSION" \
  -auto-approve

# 5. Capture outputs
QUEUE_URL=$(terraform output -raw sqs_queue_url)
ASSETS_BUCKET=$(terraform output -raw assets_bucket_name)
DLQ_URL=$(terraform output -raw dlq_url)

echo ""
echo "====================================="
echo " Wraptor deployed: $NAME"
echo "====================================="
echo ""
echo "ACTION REQUIRED:"
echo "  Check $EMAIL and click 'Confirm Subscription'"
echo "  (you won't receive failure alerts until you confirm)"
echo ""
echo "-------------------------------------"
echo " SQS Queue URL"
echo "-------------------------------------"
echo "  $QUEUE_URL"
echo ""
echo "-------------------------------------"
echo " S3 Bucket"
echo "-------------------------------------"
echo "  Bucket : s3://$ASSETS_BUCKET"
echo "  Input  : s3://$ASSETS_BUCKET/input/"
echo "  Output : s3://$ASSETS_BUCKET/output/"
echo ""
echo "-------------------------------------"
echo " Failed Jobs (DLQ)"
echo "-------------------------------------"
echo "  $DLQ_URL"
echo ""
echo "-------------------------------------"
echo " Job Format"
echo "-------------------------------------"
echo "  {"
echo "    \"job_id\":        \"any-unique-id\","
echo "    \"input_s3_path\": \"s3://$ASSETS_BUCKET/input/your-file.fasta\""
echo "  }"
echo ""
echo "  Results at: s3://$ASSETS_BUCKET/output/{job_id}/"
echo ""
echo "====================================="
