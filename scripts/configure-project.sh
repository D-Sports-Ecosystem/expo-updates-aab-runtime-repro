#!/usr/bin/env bash
# Point the MRE at your own EAS project (required before EAS builds).
# Usage: bash scripts/configure-project.sh <eas-project-id>
set -euo pipefail

PROJECT_ID="${1:?Usage: configure-project.sh <eas-project-id>}"

for f in app.json; do
  sed -i "s|YOUR-EAS-PROJECT-ID|${PROJECT_ID}|g" "$f"
done

echo "Configured EAS project id: ${PROJECT_ID}"
grep -n "u.expo.dev\|projectId" app.json
