#!/usr/bin/env bash
# Pull a Play-installed app's APKs off a connected device and grep each one
# for expo_runtime_version. Replicates the evidence step from expo/expo#48148:
# base.apk is usually correct while a split_config.<locale>.apk carries the
# stale Play-injected value.
# Usage: bash scripts/pull-device-splits.sh [android-package] [output-dir]
# Requires: adb + a device with the Play-installed build (USB debugging on).
set -euo pipefail

PKG="${1:-com.example.aabruntimerepro}"
OUT="${2:-device-splits}"
ADB="${ADB:-adb}"

command -v "$ADB" >/dev/null 2>&1 || { echo "ERROR: adb not found. Install platform-tools first."; exit 1; }
"$ADB" get-state >/dev/null 2>&1 || { echo "ERROR: no device. Connect one with USB debugging enabled."; exit 1; }

mkdir -p "$OUT"
echo "== package: $PKG"
PATHS="$("$ADB" shell pm path "$PKG" | tr -d '\r')"
[ -n "$PATHS" ] || { echo "ERROR: package $PKG not installed on device."; exit 1; }

echo "$PATHS" | while read -r line; do
  remote="${line#package:}"
  base="$(basename "$remote")"
  echo "--- pulling $base"
  "$ADB" pull "$remote" "$OUT/$base" >/dev/null
done

echo
echo "== expo_runtime_version per APK (strings scan) =="
for apk in "$OUT"/*.apk; do
  echo "--- $apk"
  unzip -p "$apk" resources.arsc 2>/dev/null | strings | grep -E "expo_runtime_version|^[0-9]+\.[0-9]+\.[0-9]+(-local-test)?$" | sort -u | head -n 6 || echo "(no resources.arsc)"
done

cat <<'EOF'

How to read this (expo/expo#48148):
  base.apk correct + split_config.<locale>.apk stale
    => Play injected a locale-qualified value server-side after upload.
       Check Play Console > Grow users > Translations > App strings,
       disable automatic translation, and upload a NEW bundle.
  every APK stale (including base.apk)
    => the value was baked at build time; compare with inspect-aab.sh.
EOF
