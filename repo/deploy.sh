#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"

echo ">>> Deploying CodeCommit repository"
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cfn.yaml" \
  --stack-name argocd-deployment-repo \
  --parameter-overrides RepositoryName=argocd-deployment \
  --no-fail-on-empty-changeset

COMMIT_ID=$(aws codecommit get-branch \
  --repository-name argocd-deployment \
  --branch-name main \
  --query 'branch.commitId' --output text)

for BRANCH in integration test-platform; do
  if aws codecommit get-branch --repository-name argocd-deployment --branch-name "$BRANCH" >/dev/null 2>&1; then
    echo ">>> Branch '$BRANCH' already exists"
  else
    echo ">>> Creating branch '$BRANCH'"
    aws codecommit create-branch \
      --repository-name argocd-deployment \
      --branch-name "$BRANCH" \
      --commit-id "$COMMIT_ID"
  fi
done

echo ">>> Done. Branches: main, integration, test-platform"
