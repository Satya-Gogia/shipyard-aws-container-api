#!/usr/bin/env bash
# Run this ON the EC2 instance (Amazon Linux 2023) over SSH.
# The instance needs an IAM role with AmazonEC2ContainerRegistryReadOnly.
# Usage: IMAGE_URI=<account>.dkr.ecr.<region>.amazonaws.com/task-api:latest ./run_on_ec2.sh
set -euo pipefail

: "${IMAGE_URI:?Set IMAGE_URI to your ECR image}"
REGION="$(echo "$IMAGE_URI" | cut -d. -f4)"
REGISTRY="${IMAGE_URI%%/*}"

# One-time Docker install
if ! command -v docker >/dev/null; then
  sudo dnf install -y docker
  sudo systemctl enable --now docker
  sudo usermod -aG docker "$USER"
fi

aws ecr get-login-password --region "$REGION" \
  | sudo docker login --username AWS --password-stdin "$REGISTRY"

sudo docker pull "$IMAGE_URI"
sudo docker rm -f task-api 2>/dev/null || true
sudo docker run -d --name task-api --restart unless-stopped -p 80:8000 "$IMAGE_URI"

echo "Running. Test: curl http://localhost/health"
