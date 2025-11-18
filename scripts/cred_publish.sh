#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat << EOF
Usage: $0-o <org> -P <project> -a <access_token> -p <packages> [-L]

Required:
  -o  Organization name
  -P  Project name
  -a  Access token
  -p  Packages to publish (space-separated: "path|name|version path|name|version")

Optional:
  -L  Pass --set-latest to 'cred publish'

Examples:
  $0 -o myorg -P myproj -a token123 -p "packages/auth|auth|1.0.1"
  $0 -o myorg -P myproj -a token123 -p "packages/auth|auth|1.0.1 packages/billing|billing|2.0.0" -L
EOF
  exit 1
}

ORGANIZATION_NAME=""
PROJECT_NAME=""
ACCESS_TOKEN=""
PACKAGES=""
SET_LATEST=false

while getopts ":e:o:P:a:p:L" opt; do
  case "$opt" in
    o) ORGANIZATION_NAME="$OPTARG" ;;
    P) PROJECT_NAME="$OPTARG" ;;
    a) ACCESS_TOKEN="$OPTARG" ;;
    p) PACKAGES="$OPTARG" ;;
    L) SET_LATEST=true ;;
    *) usage ;;
  esac
done

if [[ -z "$ORGANIZATION_NAME" || -z "$PROJECT_NAME" || -z "$ACCESS_TOKEN" || -z "$PACKAGES" ]]; then
  usage
fi

if ! command -v cred >/dev/null 2>&1; then
  echo "[setup] Installing Credible CLI..."
  npm install -g @ms2data/cred-cli
fi

echo "[setup] Organization: $ORGANIZATION_NAME"
echo "[setup] Project: $PROJECT_NAME"

# Set access token
cred set-access-token "$ACCESS_TOKEN" -o "$ORGANIZATION_NAME"

# Set default project
cred set project "$PROJECT_NAME"

# Sanity check
echo "[setup] Verifying credentials..."
if ! cred status; then
  echo "[error] Failed to authenticate with Credible CLI"
  exit 1
fi

echo "[setup] Setup complete!"
echo ""

published_count=0
skipped_count=0
failed_count=0
failed_packages=""
max_attempts=3

# Handle package names with spaces by splitting on " packages/" pattern
# This assumes all package paths start with "packages/"
# Convert space-separated items to newline-separated (split before each "packages/")
PACKAGES_ARRAY=$(echo "$PACKAGES" | sed 's/ packages\//\npackages\//g')

while IFS= read -r item; do
  # Skip empty lines
  [ -z "$item" ] && continue
  
  IFS="|" read -r path name version <<< "$item"
  
  echo "════════════════════════════════════════════════"
  echo "Package: $name@$version"
  echo "Path: $path"
  echo "════════════════════════════════════════════════"
  
  # Validate package directory
  if [ ! -d "$path" ]; then
    echo "[error] Package directory does not exist: $path"
    failed_count=$((failed_count + 1))
    failed_packages="$failed_packages $name@$version"
    echo ""
    continue
  fi
  
  # Validate publisher.json
  if [ ! -f "$path/publisher.json" ]; then
    echo "[error] No publisher.json found in: $path"
    failed_count=$((failed_count + 1))
    failed_packages="$failed_packages $name@$version"
    echo ""
    continue
  fi
  
  # Change to package directory
  pushd "$path" >/dev/null
  
  # Verify version matches
  actual_version=$(jq -r '.version' publisher.json 2>/dev/null || echo "unknown")
  actual_name=$(jq -r '.name' publisher.json 2>/dev/null || echo "$(basename $path)")
  
  if [ "$actual_version" != "$version" ]; then
    echo "[warning] Version mismatch!"
    echo "  Expected: $version"
    echo "  Found in publisher.json: $actual_version"
    echo "  Using actual version: $actual_version"
    version="$actual_version"
  fi
  
  # Retry loop for this package
  attempt=1
  package_published=false
  
  while [ $attempt -le $max_attempts ]; do
    echo "[publish] Attempt $attempt of $max_attempts for $name@$version"
    
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
    
    # Check if version already exists FIRST (before checking exit code)
    if grep -qiE "version already exists|VersionId already exists" "$PUBLISH_LOG"; then
      echo "[warning] ⚠️  Package $name@$version already exists. Skipping."
      echo "[info] The package was likely published manually or in a previous run."
      skipped_count=$((skipped_count + 1))
      package_published=true
      rm -f "$PUBLISH_LOG"
      break
    fi

    if grep -qiE "Failed to publish package|Unauthorized" "$PUBLISH_LOG"; then
      # Failed - check if we should retry
      echo "[error] ❌ Publish attempt $attempt failed for $name@$version"
      
      # Show error details on final attempt
      if [ $attempt -eq $max_attempts ]; then
        echo "[error] Final attempt failed. Error details:"
        grep -iE "error|failed" "$PUBLISH_LOG" || cat "$PUBLISH_LOG"
        echo "[error] ❌ Failed to publish $name@$version after $max_attempts attempts"
        failed_count=$((failed_count + 1))
        failed_packages="$failed_packages $name@$version"
      fi
      
      rm -f "$PUBLISH_LOG"
      
      # Wait before retry (if not final attempt)
      if [ $attempt -lt $max_attempts ]; then
        echo "[retry] Waiting 5s before retry..."
        sleep 5
      fi
      
      attempt=$((attempt + 1))
      continue
    fi

    # Success case
    if [ $PUBLISH_EXIT_CODE -eq 0 ]; then
      echo "[success] ✅ Published $name@$version successfully"
      published_count=$((published_count + 1))
      package_published=true
      rm -f "$PUBLISH_LOG"
      break
    fi
  done

  popd >/dev/null
  echo ""
done <<< "$PACKAGES_ARRAY"

echo "════════════════════════════════════════════════"
echo "PUBLISH SUMMARY"
echo "════════════════════════════════════════════════"
echo "Total packages:        $((published_count + skipped_count + failed_count))"
echo "✅ Published:          $published_count"
echo "⚠️  Skipped (exists):   $skipped_count"
echo "❌ Failed:             $failed_count"

if [ -n "$failed_packages" ]; then
  echo ""
  echo "Failed packages:$failed_packages"
fi

echo "════════════════════════════════════════════════"

# Exit with appropriate code
if [ $failed_count -gt 0 ]; then
  echo "[error] Some packages failed to publish"
  exit 1
fi

if [ $published_count -eq 0 ] && [ $skipped_count -eq 0 ]; then
  echo "[warning] No packages were published"
  exit 0
fi

echo "[success] All packages processed successfully!"
exit 0