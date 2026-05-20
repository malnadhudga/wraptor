#!/bin/bash
set -e

NAME=$1
REGION=${2:-us-east-1}

if [ -z "$NAME" ]; then
  echo "Usage: ./redeploy.sh <name> [region]"
  echo "Example: ./redeploy.sh vespag us-east-1"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
ECR_IMAGE_URI="$ECR_REGISTRY/$NAME:latest"

echo "Redeploying image: $NAME ($REGION)"

# Login to ECR
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Rebuild base and model image
echo "Building base image..."
docker build -f Dockerfile.base -t wraptor-base:latest .

echo "Building model image..."
docker build -t "$NAME:latest" .

# Push new image
docker tag "$NAME:latest" "$ECR_IMAGE_URI"
docker push "$ECR_IMAGE_URI"

echo ""
echo "Image pushed: $ECR_IMAGE_URI"
echo "New EC2 instances will use this image on next scale-out."
