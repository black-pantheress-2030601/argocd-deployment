#!/usr/bin/env bash
set -euo pipefail

DOMAIN="platform"
DOMAIN_OWNER="${ACCOUNT_ID}"
REPO="cargo"
AWS_DEFAULT_REGION="ap-southeast-2"
S3_URI="s3://my-bucket/tools/"
CARGO_HOME="$HOME/.cargo"
ARCH="$(uname -m)"                      # aarch64 or x86_64
export AWS_PAGER=""

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---- 1. AWS CLI v2 from the local zip (no network needed) ----
if ! command -v aws >/dev/null 2>&1; then
  zip="vendor/awscli-exe-linux-${ARCH}.zip"
  [ -f "$zip" ] || { echo "missing $zip" >&2; exit 1; }
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$zip" -d "$WORK"
  else
    echo "need unzi to extract the AWS CLI zip" >&2; exit 1
  fi
  "$WORK/aws/install" --install-dir /opt/aws-cli --bin-dir /usr/local/bin
fi
aws --version

# ---- 2. CodeArtifact token and cargo config ----
aws sts get-caller-identity >/dev/null
TOKEN="$(aws codeartifact get-authorization-token \
  --domain "$DOMAIN" --domain-owner "$DOMAIN_OWNER" \
  --query authorizationToken --output text)"
[ "${#TOKEN}" -gt 1000 ] || { echo "CodeArtifact token looks too short" >&2; exit 1; }
export CARGO_REGISTRIES_CODEARTIFACT_TOKEN="$TOKEN"

ENDPOINT="$(aws codeartifact get-repository-endpoint \
  --domain "$DOMAIN" --domain-owner "$DOMAIN_OWNER" \
  --repository "$REPO" --format cargo \
  --query repositoryEndpoint --output text)"

code="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: $TOKEN" "${ENDPOINT}config.json" || true)"
[ "$code" = "200" ] || { echo "CodeArtifact endpoint returned HTTP $code" >&2; exit 1; }

mkdir -p "$CARGO_HOME"
cat > "$CARGO_HOME/config.toml" <<EOF
[registries.codeartifact]
index = "sparse+${ENDPOINT}"
credential-provider = "cargo:token"

[registry]
global-credential-providers = ["cargo:token"]

[source.crates-io]
replace-with = "codeartifact"
EOF

# ---- 3. tuftool ----
# Clear the cached index first: a stale one caused a false snafu resolution error before.
rm -rf "$CARGO_HOME/registry/index" "$CARGO_HOME/registry/cache"
STAGE="$WORK/stage"
mkdir -p "$STAGE/usr/local" "$STAGE/opt"
cargo install tuftool --locked --root "$STAGE/usr/local"
"$STAGE/usr/local/bin/tuftool" --version

# ---- 4. package ----
cp -a /opt/aws-cli "$STAGE/opt/aws-cli"
ln -sf /opt/aws-cli/v2/current/bin/aws "$STAGE/usr/local/bin/aws"
{ aws --version; "$STAGE/usr/local/bin/tuftool" --version; } > "$STAGE/MANIFEST.txt" 2>&1

NAME="tools-${ARCH}-$(date -u +%Y%m%dT%H%M%SZ).tgz"
tar -C "$STAGE" -czf "$WORK/$NAME" opt usr MANIFEST.txt
( cd "$WORK" && sha256sum "$NAME" > "$NAME.sha256" )

# ---- 5. upload ----
aws s3 cp "$WORK/$NAME"        "$S3_URI/$NAME"        ${S3_SSE:+--sse "$S3_SSE"}
aws s3 cp "$WORK/$NAME.sha256" "$S3_URI/$NAME.sha256" ${S3_SSE:+--sse "$S3_SSE"}
echo "Uploaded $S3_URI/$NAME"
