#!/usr/bin/env bash
# Bump version + runtimeVersion in app.json (mirrors how production ships:
# top-level string runtimeVersion AND explicit android.runtimeVersion).
# Usage: bash scripts/bump-runtime.sh <new-version> [new-version-code]
set -euo pipefail

NEW_VERSION="${1:?Usage: bump-runtime.sh <new-version> [new-version-code]}"
NEW_CODE="${2:-}"

python3 - "$NEW_VERSION" "$NEW_CODE" <<'EOF'
import json, sys

new_version, new_code = sys.argv[1], sys.argv[2]
path = 'app.json'
with open(path) as f:
    doc = json.load(f)

expo = doc['expo']
expo['version'] = new_version
expo['runtimeVersion'] = new_version
expo['android']['runtimeVersion'] = new_version
if new_code:
    expo['android']['versionCode'] = int(new_code)
else:
    expo['android']['versionCode'] = int(expo['android'].get('versionCode', 0)) + 1

with open(path, 'w') as f:
    json.dump(doc, f, indent=2)
    f.write('\n')

print(f"version={expo['version']} runtimeVersion={expo['runtimeVersion']} "
      f"android.runtimeVersion={expo['android']['runtimeVersion']} "
      f"versionCode={expo['android']['versionCode']}")
EOF

git diff -- app.json | head -n 40 || true
