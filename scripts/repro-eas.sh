#!/usr/bin/env bash
# Full EAS repro sequence. Default is DRY RUN (prints every command).
# Pass --execute to run the EAS builds (needs `eas login` + configured project id).
#
# Sequence:
#   v1 (current app.json) -> eas build apk   [control arm, expected correct]
#   bump to v2            -> eas build apk   [control arm, expected correct]
#                        -> eas build aab   [experimental arm -> Play internal track]
#   install both v2 binaries, screenshot the app screen, compare
#   Updates.runtimeVersion. Publish an OTA update pinned to v2 and watch the
#   Play build reject it (updateRejectedBySelectionPolicy).
set -euo pipefail

EXECUTE="false"
[ "${1:-}" = "--execute" ] && EXECUTE="true"

cd "$(dirname "$0")/.."

if grep -q "YOUR-EAS-PROJECT-ID" app.json; then
  echo "ERROR: app.json still has YOUR-EAS-PROJECT-ID."
  echo "Run: bash scripts/configure-project.sh <your-eas-project-id>"
  echo "Get one with: npx eas-cli init  (or reuse an existing project id)"
  exit 1
fi

V1="$(python3 -c "import json; print(json.load(open('app.json'))['expo']['version'])")"
echo "v1 = $V1 (current app.json)"
echo "v2 = bumped version (you pick it, e.g. 2.0.0)"
echo

run() {
  if [ "$EXECUTE" = "true" ]; then
    echo "+ $*"
    "$@"
  else
    echo "DRY-RUN> $*"
  fi
}

echo "== Step 1: APK at v1 (control) =="
run eas build --platform android --profile apk --non-interactive

echo
echo "== Step 2: bump version/runtimeVersion =="
echo "DRY-RUN> bash scripts/bump-runtime.sh 2.0.0"
[ "$EXECUTE" = "true" ] && bash scripts/bump-runtime.sh 2.0.0

echo
echo "== Step 3: APK at v2 (control, sideload it) =="
run eas build --platform android --profile apk --non-interactive

echo
echo "== Step 4: AAB at v2 (experimental, upload to Play internal track) =="
run eas build --platform android --profile aab --non-interactive

cat <<'EOF'

== Step 5: install + compare (on one device, same locale) ==
  1. Sideload the v2 APK, open the app, screenshot the whole screen.
  2. Upload the v2 AAB to Play Console > Internal testing, install from Play,
     open the app, screenshot the whole screen.
  3. Expected: Updates.runtimeVersion == 2.0.0 on BOTH.
     Actual (bug): Play build shows the v1 value.
  4. Screenshot Play Console > Grow users > Translations > App strings
     (automatic app-string translation on/off? prime suspect per #48148).
  5. Locale-switch test: switch device language to English, reinstall the
     Play build, re-read Updates.runtimeVersion. Flips to correct?
     => Play-injected locale split is overriding the default.
  6. With adb: bash scripts/pull-device-splits.sh > evidence/device-splits.txt

== Step 6 (optional): prove OTA rejection ==
  1. eas update --channel production --message "ota-vs-v2"
  2. Relaunch both apps. The Play build logs updateRejectedBySelectionPolicy
     (stale native runtime mismatches the update's runtime); the APK updates.

== Step 7: binary forensics (no device needed) ==
  bash scripts/inspect-apk.sh <v2.apk>   # expect expo_runtime_version = v2
  bash scripts/inspect-aab.sh <v2.aab>   # stale here => baked at EAS build time
EOF

[ "$EXECUTE" = "false" ] && echo && echo "(Pass --execute to run the eas commands. Nothing was built.)"
