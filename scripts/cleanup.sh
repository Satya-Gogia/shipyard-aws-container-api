#!/usr/bin/env bash
# Tear down ECS resources + ECR repo so you don't pay for them. EC2: terminate it in the console.
set -uo pipefail
AWS_REGION="${AWS_REGION:-ap-south-1}"
aws ecs update-service --cluster task-api-cluster --service task-api-service --desired-count 0 --region "$AWS_REGION" >/dev/null
aws ecs delete-service --cluster task-api-cluster --service task-api-service --force --region "$AWS_REGION" >/dev/null
aws ecs delete-cluster --cluster task-api-cluster --region "$AWS_REGION" >/dev/null
aws ecr delete-repository --repository-name task-api --force --region "$AWS_REGION" >/dev/null
aws logs delete-log-group --log-group-name /ecs/task-api --region "$AWS_REGION"
echo "Cleaned up."
