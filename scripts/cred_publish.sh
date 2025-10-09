#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Usage: $0 -e <staging|prod> -o <org> -P <project> -a <access_token> -d <packages/<name>> [-L]"
  echo "  -L  Pass --set-latest to 'cred publish'"
  exit 1
}

ENVIRONMENT="" ORGANIZATION_NAME="" PROJECT_NAME="" ACCESS_TOKEN="" PKG_DIR="" SET_LATEST=false

while getopts ":e:o:P:a:d:L" opt; do
  case "$opt" in
    e) ENVIRONMENT="$OPTARG" ;;
    o) ORGANIZATION_NAME="$OPTARG" ;;
    P) PROJECT_NAME="$OPTARG" ;;
    a) ACCESS_TOKEN="$OPTARG" ;;
    d) PKG_DIR="$OPTARG" ;;
    L) SET_LATEST=true ;;
    *) usage ;;
  esac
done

if [[ -z "$ENVIRONMENT" || -z "$ORGANIZATION_NAME" || -z "$PROJECT_NAME" || -z "$ACCESS_TOKEN" || -z "$PKG_DIR" ]]; then
  usage
fi

# Ensure CLI is installed
if ! command -v cred >/dev/null 2>&1; then
  echo "[setup] Installing Credible CLI..."
  npm install -g @ms2data/cred-cli
fi

echo "[setup] Setting up environment: $ENVIRONMENT"
echo "[setup] Organization: $ORGANIZATION_NAME"
echo "[setup] Project: $PROJECT_NAME"

# 1. Set access token
cred set-access-token "$ACCESS_TOKEN" -o "$ORGANIZATION_NAME"

# 2. Set default project
cred set project "$PROJECT_NAME"

# 3. Sanity check
cred status || true

# 4. Publish package
echo "[publish] Starting publish for package at $PKG_DIR"
pushd "$PKG_DIR" >/dev/null
if $SET_LATEST; then
  echo "[publish] Using --set-latest flag"
  cred publish --set-latest
else
  cred publish
fi
popd >/dev/null

echo "[done] Publish complete for $PKG_DIR"
