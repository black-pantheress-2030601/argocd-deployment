#!/usr/bin/env bash
set -euo pipefail

aws cloudformation deploy \
  --template-file "$(dirname "$0")/code-repo.yaml" \
  --stack-name argocd-deployment-repo \
  --parameter-overrides RepositoryName=argocd-deployment \
  --no-fail-on-empty-changeset
