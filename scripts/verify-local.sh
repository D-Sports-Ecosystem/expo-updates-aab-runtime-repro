#!/usr/bin/env bash
# LOCAL verification: no EAS account, no Play Console needed.
# Runs `expo prebuild --platform android` and greps the generated
# strings.xml / AndroidManifest.xml for expo_runtime_version.
#
# Phases:
#   1. Clean prebuild at v1 -> expect v1 baked in.
#   2. Bump to v2, DIRTY prebuild (existing android/ kept) -> tests whether
#      prebuild-on-existing-project or config-plugin ordering carries a stale value.
#   3. Clean prebuild at v2 -> expect v2 baked in.
#   4. Locales shadowing: temporarily wire locales/*.json containing a STALE
#      expo_runtime_version, clean prebuild, and show the qualified
#      values-b+<lang>/strings.xml shadowing the fresh default.
#   5. Restore app.json + final clean prebuild at v1 (repo left pristine).
set -euo pipefail

cd "$(dirname "$0")/.."

STRINGS="android/app/src/main/res/values/strings.xml"
MANIFEST="android/app/src/main/AndroidManifest.xml"
BACKUP="app.json.verify-backup"

show_baked() {
  echo "--- $STRINGS (expo_runtime_version) ---"
  grep -o '<string name="expo_runtime_version">[^<]*</string>' "$STRINGS" || echo "(missing!)"
  echo "--- $MANIFEST (EXPO_RUNTIME_VERSION) ---"
  grep -o 'expo\.modules\.updates\.EXPO_RUNTIME_VERSION[^>]*' "$MANIFEST" | head -n 2 || echo "(missing!)"
  echo "--- all expo_runtime_version string files ---"
  grep -rl "expo_runtime_version" android/app/src/main/res/ | sort
}

cleanup_restore() {
  if [ -f "$BACKUP" ]; then
    mv "$BACKUP" app.json
  fi
}
trap cleanup_restore EXIT
cp app.json "$BACKUP"

V1="$(python3 -c "import json; print(json.load(open('app.json'))['expo']['version'])")"
V2="$(python3 -c "
v = '$V1'.split('-')[0].split('.')
v[-1] = str(int(v[-1]) + 1) if v[-1].isdigit() else '1'
print('.'.join(v) + '-local-test')
")"

echo "================================================================"
echo "Phase 1: clean prebuild at v1 ($V1)"
echo "================================================================"
rm -rf android
npx expo prebuild --platform android --non-interactive >/tmp/prebuild-p1.log 2>&1
show_baked

echo
echo "================================================================"
echo "Phase 2: bump to v2 ($V2), DIRTY prebuild (android/ kept)"
echo "================================================================"
bash scripts/bump-runtime.sh "$V2" >/dev/null
npx expo prebuild --platform android --non-interactive >/tmp/prebuild-p2.log 2>&1
show_baked

echo
echo "================================================================"
echo "Phase 3: clean prebuild at v2 ($V2)"
echo "================================================================"
rm -rf android
npx expo prebuild --platform android --non-interactive >/tmp/prebuild-p3.log 2>&1
show_baked

echo
echo "================================================================"
echo "Phase 4: locales shadowing (stale expo_runtime_version in en.json)"
echo "================================================================"
mkdir -p locales
cat > locales/en.json <<EOF
{
  "appName": "aab-runtime-repro",
  "expo_runtime_version": "$V1"
}
EOF
python3 -c "
import json
doc = json.load(open('app.json'))
doc['expo']['locales'] = {'en': './locales/en.json'}
json.dump(doc, open('app.json', 'w'), indent=2)
open('app.json', 'a').write('\n')
"
rm -rf android
npx expo prebuild --platform android --non-interactive >/tmp/prebuild-p4.log 2>&1
echo "--- default values/strings.xml (fresh, from runtimeVersion=$V2) ---"
grep -o '<string name="expo_runtime_version">[^<]*</string>' "$STRINGS" || echo "(missing!)"
echo "--- values-b+en/strings.xml (stale, from locales/en.json=$V1) ---"
cat android/app/src/main/res/values-b+en/strings.xml
echo
echo "NOTE: on an en-locale device, Android resolves @string/expo_runtime_version"
echo "to the QUALIFIED (stale) value, shadowing the correct default."
rm -rf locales

echo
echo "================================================================"
echo "Phase 5: restore app.json, final clean prebuild at v1"
echo "================================================================"
mv "$BACKUP" app.json
rm -rf android
npx expo prebuild --platform android --non-interactive >/tmp/prebuild-p5.log 2>&1
show_baked

echo
echo "================================================================"
echo "LOCAL SUMMARY (see README for the Play-side steps)"
echo "================================================================"
echo "Phases 1-3 show what plain prebuild bakes in; compare each phase's"
echo "<string> line with the phase's expected version above."
echo "Phase 4 proves locale-qualified expo_runtime_version shadows the default."
echo "What still needs Jon + Play: EAS apk/aab builds at v2, Play upload of the"
echo "AAB, and the on-device Updates.runtimeVersion screenshot comparison."
