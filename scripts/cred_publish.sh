#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Usage: $0 -o <org> -P <project> -a <access_token> -d <packages/<name>> [-L]"
  echo "  -L  Pass --set-latest to 'cred publish'"
  exit 1
}


ORGANIZATION_NAME="" PROJECT_NAME="" ACCESS_TOKEN="" PKG_DIR="" SET_LATEST=false

while getopts ":o:P:a:d:L" opt; do
  case "$opt" in
    o) ORGANIZATION_NAME="$OPTARG" ;;
    P) PROJECT_NAME="$OPTARG" ;;
    a) ACCESS_TOKEN="$OPTARG" ;;
    d) PKG_DIR="$OPTARG" ;;
    L) SET_LATEST=true ;;
    *) usage ;;
  esac
done

if [[ -z "$ORGANIZATION_NAME" || -z "$PROJECT_NAME" || -z "$ACCESS_TOKEN" || -z "$PKG_DIR" ]]; then
  usage
fi

if ! command -v cred >/dev/null 2>&1; then
  echo "[setup] Installing Credible CLI..."
  npm install -g @ms2data/cred-cli
fi

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

if [ ! -d "$PKG_DIR" ]; then
  echo "[error] Package directory does not exist: $PKG_DIR"
  exit 1
fi

pushd "$PKG_DIR" >/dev/null

# Extract package info
VERSION=$(jq -r '.version' publisher.json 2>/dev/null || echo "unknown")
PACKAGE_NAME=$(jq -r '.name' publisher.json 2>/dev/null || echo "unknown")
echo "[publish] Package: $PACKAGE_NAME@$VERSION"

# Create temporary file for capturing output
PUBLISH_LOG=$(mktemp)

# Attempt to publish
PUBLISH_EXIT_CODE=0
if $SET_LATEST; then
  echo "[publish] Using --set-latest flag"
  cred publish --yes --set-latest 2>&1 | tee "$PUBLISH_LOG" || PUBLISH_EXIT_CODE=$?
else
  cred publish --yes 2>&1 | tee "$PUBLISH_LOG" || PUBLISH_EXIT_CODE=$?
fi

# Publish failed - check if it's a version collision or duplicate
if grep -qiE "version already exists|VersionId already exists" "$PUBLISH_LOG"; then
  echo "[warning] Package $PACKAGE_NAME@$VERSION already exists. Skipping."
  echo "[info] The package was likely published manually or in a previous run. if you want to publish a new version, please update the version in the publisher.json file and push a new commit."
  rm -f "$PUBLISH_LOG"
  popd >/dev/null
  exit 0
fi

# Check for any errors
if grep -qiE "ERROR:|Failed to publish" "$PUBLISH_LOG"; then
  echo "[error] Publish failed for $PACKAGE_NAME@$VERSION"
  echo "[error] Error details:"
  grep -i "error" "$PUBLISH_LOG" || cat "$PUBLISH_LOG"
  rm -f "$PUBLISH_LOG"
  popd >/dev/null
  exit 1
fi


# Check the result
if [ $PUBLISH_EXIT_CODE -eq 0 ]; then
  echo "[success] Published $PACKAGE_NAME@$VERSION successfully"
  rm -f "$PUBLISH_LOG"
  popd >/dev/null
  exit 0
fi