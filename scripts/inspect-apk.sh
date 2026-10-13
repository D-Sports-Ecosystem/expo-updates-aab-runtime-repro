#!/usr/bin/env bash
# Inspect a local APK for its embedded expo-updates runtimeVersion.
# Works with plain unzip + strings (no Android SDK needed).
# Usage: bash scripts/inspect-apk.sh <app.apk>
set -euo pipefail

APK="${1:?Usage: inspect-apk.sh <app.apk>}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== APK: $APK"
unzip -p "$APK" resources.arsc > "$WORK/resources.arsc"
echo "--- expo_runtime_version occurrences in resources.arsc ---"
strings "$WORK/resources.arsc" | grep -n "expo_runtime_version" || echo "(none found)"
echo "--- nearby version-like strings ---"
strings "$WORK/resources.arsc" | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" | sort -u | head -n 10 || true

if unzip -l "$APK" | grep -q "assets/app.config"; then
  echo "--- assets/app.config (JS-side config) ---"
  unzip -p "$APK" assets/app.config | python3 -c "
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

if command -v aapt2 >/dev/null 2>&1; then
  echo "--- aapt2 dump (EXPO_RUNTIME_VERSION) ---"
  aapt2 dump xmltree "$APK" --file AndroidManifest.xml 2>/dev/null | grep -A2 -i "RUNTIME_VERSION" | head -n 10 || true
else
  echo "(aapt2 not installed — skipping manifest dump; strings output above is sufficient)"
fi
