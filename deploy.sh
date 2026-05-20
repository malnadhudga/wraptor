#!/bin/bash
set -e

NAME=$1
EMAIL=$2
REGION=${3:-us-east-1}
# Extra env vars passed as KEY=VALUE after region
# e.g. ./deploy.sh chronos-generation user@email.com us-east-1 MODEL_ID=amazon/chronos-t5-small VALUE_COL=generation_kw
shift 3 2>/dev/null || shift $#
EXTRA_ARGS=("$@")

if [ -z "$NAME" ] || [ -z "$EMAIL" ]; then
  echo "Usage: ./deploy.sh <name> <email> [region] [KEY=VALUE ...]"
  echo "Example: ./deploy.sh vespag user@example.com us-east-1"
  echo "Example: ./deploy.sh chronos-gen user@example.com us-east-1 MODEL_ID=amazon/chronos-t5-small VALUE_COL=generation_kw"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
ECR_IMAGE_URI="$ECR_REGISTRY/$NAME:latest"

# Build extra_env map for Terraform from KEY=VALUE args
EXTRA_ENV_TF="{"
for kv in "${EXTRA_ARGS[@]}"; do
  KEY="${kv%%=*}"
  VAL="${kv#*=}"
  EXTRA_ENV_TF+="\"$KEY\"=\"$VAL\","
done
EXTRA_ENV_TF="${EXTRA_ENV_TF%,}}"

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
  -var="input_extension=.csv" \
  -var="extra_env=$EXTRA_ENV_TF" \
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
echo "    \"input_s3_path\": \"s3://$INPUT_BUCKET/your-data.csv\""
echo "  }"
echo ""
echo "  Results at: s3://$OUTPUT_BUCKET/{job_id}/"
echo ""
echo "====================================="
