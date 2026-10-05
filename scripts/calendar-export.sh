#!/usr/bin/env bash
set -euo pipefail
source /root/.calendar-env

OUT=/opt/appdata/homepage/calendars
mkdir -p "$OUT"

declare -A CALS=(
  [uni]=uni-classes
  [assignments]=assignments
  [personal]=85753f49-46d7-7c64-43aa-a747774d7b38
)

for name in "${!CALS[@]}"; do
  curl -fsS -u "$RADICALE_USER:$RADICALE_PASS" \
    "$RADICALE_URL/oni/${CALS[$name]}/?export" \
    -o "$OUT/$name.ics" || echo "warn: export failed for $name"
done
chmod 644 "$OUT"/*.ics
chown -R 1000:1000 "$OUT"
