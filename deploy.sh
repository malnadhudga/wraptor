#!/bin/bash
set -e

NAME=$1
EMAIL=$2
REGION=${3:-us-east-1}

if [ -z "$NAME" ] || [ -z "$EMAIL" ]; then
  echo "Usage: ./deploy.sh <name> <email> [region]"
  echo "Example: ./deploy.sh vespag user@example.com us-east-1"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
ECR_IMAGE_URI="$ECR_REGISTRY/$NAME:latest"

echo "Deploying Wraptor: $NAME ($REGION)"

# 1. Create ECR repo (skip if exists)
aws ecr create-repository --repository-name "$NAME" --region "$REGION" 2>/dev/null || true

# 2. Login to ECR
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

# 3. Build base image
echo "Building base image..."
docker build -f Dockerfile.base -t wraptor-base:latest .

# 4. Build model image
echo "Building model image..."
docker build -t "$NAME:latest" .

# 5. Tag and push
docker tag "$NAME:latest" "$ECR_IMAGE_URI"
docker push "$ECR_IMAGE_URI"

# 6. Terraform
cd infra/
terraform init -upgrade
terraform apply \
  -var="name=$NAME" \
  -var="region=$REGION" \
  -var="email=$EMAIL" \
  -var="ecr_image_uri=$ECR_IMAGE_URI" \
  -auto-approve

# 7. Capture outputs
QUEUE_URL=$(terraform output -raw sqs_queue_url)
INPUT_BUCKET=$(terraform output -raw input_bucket_name)
OUTPUT_BUCKET=$(terraform output -raw output_bucket_name)
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
echo " S3 Buckets"
echo "-------------------------------------"
echo "  Input  : s3://$INPUT_BUCKET"
echo "  Output : s3://$OUTPUT_BUCKET"
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
echo "    \"input_s3_path\": \"s3://$INPUT_BUCKET/your-file.fasta\""
echo "  }"
echo ""
echo "  Results at: s3://$OUTPUT_BUCKET/{job_id}/"
echo ""
echo "====================================="
