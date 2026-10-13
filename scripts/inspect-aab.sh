#!/usr/bin/env bash
# Inspect a local AAB for its embedded expo-updates runtimeVersion.
# AAB resources live in protobuf (base/resources.pb); plain strings still
# reveals the baked-in values. bundletool gives the full picture when present.
# Usage: bash scripts/inspect-aab.sh <app.aab>
set -euo pipefail

AAB="${1:?Usage: inspect-aab.sh <app.aab>}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== AAB: $AAB"
echo "--- modules ---"
unzip -l "$AAB" | grep -E "resources.pb|Manifest" | head -n 10

unzip -p "$AAB" base/resources.pb > "$WORK/resources.pb" 2>/dev/null || true
if [ -s "$WORK/resources.pb" ]; then
  echo "--- expo_runtime_version occurrences in base/resources.pb ---"
  strings "$WORK/resources.pb" | grep -n "expo_runtime_version" || echo "(none found)"
  echo "--- version-like strings ---"
  strings "$WORK/resources.pb" | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" | sort -u | head -n 10 || true
fi

if unzip -l "$AAB" | grep -q "base/assets/app.config"; then
  echo "--- base/assets/app.config (JS-side config) ---"
  unzip -p "$AAB" base/assets/app.config | python3 -c "
import json, sys
c = json.load(sys.stdin)
print('version:', c.get('version'))
print('runtimeVersion:', c.get('runtimeVersion'))
print('android.runtimeVersion:', (c.get('android') or {}).get('runtimeVersion'))
print('android.versionCode:', (c.get('android') or {}).get('versionCode'))
print('updates.url:', (c.get('updates') or {}).get('url'))
print('locales:', c.get('locales'))
"
fi

if command -v bundletool >/dev/null 2>&1; then
  echo "--- bundletool dump manifest ---"
  bundletool dump manifest --bundle="$AAB" 2>/dev/null | grep -i -A1 "RUNTIME_VERSION" | head -n 6 || true
  echo "--- bundletool dump resources (expo_runtime_version) ---"
  bundletool dump resources --bundle="$AAB" 2>/dev/null | grep -i -B2 -A2 "expo_runtime_version" | head -n 20 || true
else
  echo "(bundletool not installed — for full AAB resource tables see"
  echo " https://developer.android.com/tools/bundletool, or run scripts/repro-eas.sh)"
fi
