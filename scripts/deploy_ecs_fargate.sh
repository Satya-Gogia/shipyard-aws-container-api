#!/usr/bin/env bash
# Deploy the ECR image to ECS Fargate using the default VPC.
# Usage: IMAGE_URI=... AWS_REGION=ap-south-1 ./scripts/deploy_ecs_fargate.sh
set -euo pipefail

: "${IMAGE_URI:?Set IMAGE_URI to your ECR image}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER="task-api-cluster"
SERVICE="task-api-service"
FAMILY="task-api"
SG_NAME="task-api-sg"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# 1. Execution role so Fargate can pull from ECR and write logs
if ! aws iam get-role --role-name ecsTaskExecutionRole >/dev/null 2>&1; then
  aws iam create-role --role-name ecsTaskExecutionRole \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
fi

# 2. Cluster + log group
aws ecs create-cluster --cluster-name "$CLUSTER" --region "$AWS_REGION" >/dev/null
aws logs create-log-group --log-group-name /ecs/task-api --region "$AWS_REGION" 2>/dev/null || true

# 3. Networking: default VPC, open port 8000
VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION")"
SUBNETS="$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[].SubnetId' --output text --region "$AWS_REGION" | tr '\t' ',')"
SG_ID="$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SG_NAME" Name=vpc-id,Values="$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text --region "$AWS_REGION")"
if [ "$SG_ID" = "None" ]; then
  SG_ID="$(aws ec2 create-security-group --group-name "$SG_NAME" --description "task-api" --vpc-id "$VPC_ID" --query GroupId --output text --region "$AWS_REGION")"
  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 8000 --cidr 0.0.0.0/0 --region "$AWS_REGION" >/dev/null
fi

# 4. Task definition
cat > /tmp/taskdef.json <<JSON
{
  "family": "$FAMILY",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "containerDefinitions": [{
    "name": "task-api",
    "image": "$IMAGE_URI",
    "essential": true,
    "portMappings": [{"containerPort": 8000, "protocol": "tcp"}],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {"awslogs-group": "/ecs/task-api", "awslogs-region": "$AWS_REGION", "awslogs-stream-prefix": "ecs"}
    }
  }]
}
JSON
aws ecs register-task-definition --cli-input-json file:///tmp/taskdef.json --region "$AWS_REGION" >/dev/null

# 5. Service (create, or roll the existing one)
if aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$AWS_REGION" --query 'services[?status==`ACTIVE`]' --output text | grep -q .; then
  aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --task-definition "$FAMILY" --force-new-deployment --region "$AWS_REGION" >/dev/null
else
  aws ecs create-service --cluster "$CLUSTER" --service-name "$SERVICE" --task-definition "$FAMILY" \
    --desired-count 1 --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
    --region "$AWS_REGION" >/dev/null
fi

echo "Deployed. Find the task's public IP:"
echo "  TASK=\$(aws ecs list-tasks --cluster $CLUSTER --query 'taskArns[0]' --output text --region $AWS_REGION)"
echo "  ENI=\$(aws ecs describe-tasks --cluster $CLUSTER --tasks \$TASK --region $AWS_REGION --query 'tasks[0].attachments[0].details[?name==\`networkInterfaceId\`].value' --output text)"
echo "  aws ec2 describe-network-interfaces --network-interface-ids \$ENI --query 'NetworkInterfaces[0].Association.PublicIp' --output text --region $AWS_REGION"
