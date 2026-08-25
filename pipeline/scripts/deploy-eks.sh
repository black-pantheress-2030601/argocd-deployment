#!/usr/bin/env bash
set -euo pipefail

IFS=',' read -ra ACCOUNTS <<< "$TARGET_ACCOUNTS"
FAILED=0

for ACCOUNT_ID in "${ACCOUNTS[@]}"; do
  echo ">>> Deploying to account $ACCOUNT_ID (env: $ENVIRONMENT)"

  ACCOUNT_CONFIG="pipeline/accounts/${ENVIRONMENT}/${ACCOUNT_ID}.yaml"
  if [ ! -f "$ACCOUNT_CONFIG" ]; then
    echo "!!! No config found at $ACCOUNT_CONFIG"
    exit 1
  fi

  NODE_INSTANCE_TYPE=$(yq -r '.NodeInstanceType' "$ACCOUNT_CONFIG")
  NODE_DESIRED_SIZE=$(yq -r '.NodeDesiredSize' "$ACCOUNT_CONFIG")
  NODE_MIN_SIZE=$(yq -r '.NodeMinSize' "$ACCOUNT_CONFIG")
  NODE_MAX_SIZE=$(yq -r '.NodeMaxSize' "$ACCOUNT_CONFIG")

  CREDS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${CROSS_ACCOUNT_ROLE}" \
    --role-session-name "eks-${ENVIRONMENT}-${CODEBUILD_BUILD_NUMBER}" \
    --duration-seconds 3600 \
    --output json)

  export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
  export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
  export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')

  VPC_ID=$(aws ssm get-parameter --name "$SSM_VPC_ID_KEY" --query 'Parameter.Value' --output text)
  SUBNET_IDS=$(aws ssm get-parameter --name "$SSM_SUBNET_IDS_KEY" --query 'Parameter.Value' --output text)
  SUBNET_1=$(echo $SUBNET_IDS | cut -d',' -f1)
  SUBNET_2=$(echo $SUBNET_IDS | cut -d',' -f2)
  SUBNET_3=$(echo $SUBNET_IDS | cut -d',' -f3)

  aws cloudformation deploy \
    --template-file standalone-eks-cluster.yaml \
    --stack-name "standalone-eks-${ENVIRONMENT}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      ClusterName="standalone-cluster-${ENVIRONMENT}" \
      VpcId=$VPC_ID \
      Subnet1Id=$SUBNET_1 \
      Subnet2Id=$SUBNET_2 \
      Subnet3Id=$SUBNET_3 \
      NodeInstanceType=$NODE_INSTANCE_TYPE \
      NodeDesiredSize=$NODE_DESIRED_SIZE \
      NodeMinSize=$NODE_MIN_SIZE \
      NodeMaxSize=$NODE_MAX_SIZE \
    --no-fail-on-empty-changeset || FAILED=1

  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

  if [ $FAILED -eq 1 ]; then
    echo "!!! Deployment failed for account $ACCOUNT_ID"
    exit 1
  fi

  echo ">>> Account $ACCOUNT_ID complete"
done
