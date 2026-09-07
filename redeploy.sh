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

# Read the build resources provisioned by deploy.sh
cd infra/
ASSETS_BUCKET=$(terraform output -raw assets_bucket_name)
CODEBUILD_PROJECT=$(terraform output -raw codebuild_project)
cd ..

# Rebuild and push the image with AWS CodeBuild
./build_image.sh "$NAME" "$REGION" "$ASSETS_BUCKET" "$CODEBUILD_PROJECT" "$ECR_REGISTRY" "$ECR_IMAGE_URI"

echo ""
echo "Image pushed: $ECR_IMAGE_URI"
echo "New EC2 instances will use this image on next scale-out."
