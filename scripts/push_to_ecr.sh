#!/usr/bin/env bash
# Build the image and push it to ECR. Creates the repo if it doesn't exist.
# Usage: AWS_REGION=ap-south-1 ./scripts/push_to_ecr.sh
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
REPO_NAME="${REPO_NAME:-task-api}"
TAG="${TAG:-latest}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URI="${REGISTRY}/${REPO_NAME}:${TAG}"

aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$AWS_REGION" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name "$REPO_NAME" --region "$AWS_REGION" \
       --image-scanning-configuration scanOnPush=true >/dev/null

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

# --platform matters if you build on an Apple Silicon Mac and deploy to x86 EC2/Fargate
docker build --platform linux/amd64 -t "$IMAGE_URI" .
docker push "$IMAGE_URI"

echo "Pushed: $IMAGE_URI"
