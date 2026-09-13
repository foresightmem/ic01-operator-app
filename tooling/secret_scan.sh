#!/usr/bin/env bash
set -euo pipefail

files="$(mktemp)"
trap 'rm -f "$files"' EXIT

scan() {
  local pattern="$1"

  grep -REIl \
    --exclude-dir=.git \
    --exclude-dir=build \
    --exclude-dir=.dart_tool \
    --exclude='*.lock' \
    "$pattern" \
    lib supabase docs .github 2>/dev/null || true
}

{
  scan 'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
  scan 'sb_secret_'
  scan "SUPABASE_SERVICE_ROLE_KEY[[:space:]]*[:=][[:space:]]*[\"']?[^\"' <$]+"
  scan 'postgres(ql)?://[^[:space:]@]+:[^[:space:]@]+@'
} | sort -u > "$files"

if [[ -s "$files" ]]; then
  echo "High-risk secret-looking patterns found in:"
  cat "$files"
  exit 1
fi
