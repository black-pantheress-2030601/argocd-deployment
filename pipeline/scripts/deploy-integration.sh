#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
PIPELINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CFN_TEMPLATE="${PIPELINE_DIR}/cfn/pipeline.yaml"
ENV_FILE="${PIPELINE_DIR}/environments/integration.yaml"
ACCOUNT_DIR="${PIPELINE_DIR}/accounts/integration"

PARAMS=""
while IFS=': ' read -r key value; do
  [ -z "$key" ] && continue
  PARAMS="$PARAMS $key=$value"
done < "$ENV_FILE"

ACCOUNT_IDS=""
for ACCOUNT_FILE in "$ACCOUNT_DIR"/*.yaml; do
  ACCT=$(basename "$ACCOUNT_FILE" .yaml)
  ACCOUNT_IDS="${ACCOUNT_IDS:+${ACCOUNT_IDS},}${ACCT}"
done

aws cloudformation deploy \
  --template-file "$CFN_TEMPLATE" \
  --stack-name eks-pipeline-integration \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    $PARAMS \
    TargetAccountIds="$ACCOUNT_IDS" \
  --no-fail-on-empty-changeset
