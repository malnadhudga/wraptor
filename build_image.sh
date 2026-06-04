#!/bin/bash
# Packages the repo, uploads it to the CodeBuild source bucket, and runs the
# CodeBuild project that builds the worker image and pushes it to ECR.
#
# Usage: ./build_image.sh <name> <region> <source_bucket> <codebuild_project> <ecr_registry> <ecr_image_uri>
set -e

NAME=$1
REGION=$2
SOURCE_BUCKET=$3
CODEBUILD_PROJECT=$4
ECR_REGISTRY=$5
ECR_IMAGE_URI=$6

SOURCE_ZIP="$(mktemp -d)/source.zip"

# Package the repo (excluding local-only and infra dirs) into a zip for CodeBuild.
echo "Packaging source..."
python3 - "$SOURCE_ZIP" <<'PY'
import os, sys, zipfile
out = sys.argv[1]
skip_dirs = {".git", "venv", ".terraform", "__pycache__"}
skip_top = {"infra"}
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        top = os.path.relpath(root, ".").split(os.sep)[0]
        if top in skip_top:
            dirs[:] = []
            continue
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, "."))
print("Packaged:", out)
PY

echo "Uploading source to s3://$SOURCE_BUCKET/source.zip ..."
aws s3 cp "$SOURCE_ZIP" "s3://$SOURCE_BUCKET/source.zip" --region "$REGION"

echo "Starting CodeBuild project: $CODEBUILD_PROJECT ..."
BUILD_ID=$(aws codebuild start-build \
  --project-name "$CODEBUILD_PROJECT" \
  --region "$REGION" \
  --environment-variables-override \
    "name=ECR_REGISTRY,value=$ECR_REGISTRY,type=PLAINTEXT" \
    "name=ECR_IMAGE_URI,value=$ECR_IMAGE_URI,type=PLAINTEXT" \
    "name=IMAGE_NAME,value=$NAME,type=PLAINTEXT" \
  --query 'build.id' --output text)

echo "Build started: $BUILD_ID"
echo "Waiting for build to finish (this can take several minutes)..."
while true; do
  STATUS=$(aws codebuild batch-get-builds --ids "$BUILD_ID" --region "$REGION" \
    --query 'builds[0].buildStatus' --output text)
  case "$STATUS" in
    SUCCEEDED)
      echo "Build succeeded."
      break
      ;;
    FAILED | FAULT | STOPPED | TIMED_OUT)
      echo "Build failed with status: $STATUS"
      echo "Inspect logs: aws codebuild batch-get-builds --ids $BUILD_ID --region $REGION"
      exit 1
      ;;
    *)
      echo "  status: $STATUS ..."
      sleep 15
      ;;
  esac
done

echo "Image pushed: $ECR_IMAGE_URI"
