#!/bin/bash
set -e

NAME=$1
REGION=${2:-us-east-1}

if [ -z "$NAME" ]; then
  echo "Usage: ./destroy.sh <name> [region]"
  echo "Example: ./destroy.sh vespag us-east-1"
  exit 1
fi

echo "WARNING: This will destroy all AWS resources for: $NAME"
read -p "Are you sure? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

cd infra/
terraform destroy \
  -var="name=$NAME" \
  -var="region=$REGION" \
  -var="email=placeholder@example.com" \
  -var="ecr_image_uri=placeholder" \
  -auto-approve

echo ""
echo "All resources for $NAME have been destroyed."
