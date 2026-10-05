#!/usr/bin/env bash
# Baseline SMART audit. Run before trusting any drive with data (doc 01).
set -euo pipefail

echo "=== Drive inventory ==="
lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINT

for dev in /dev/sd?; do
  [ -b "$dev" ] || continue
  echo
  echo "=== $dev ==="
  sudo smartctl -i "$dev" | grep -E "Device Model|Serial Number|User Capacity" || true
  sudo smartctl -H "$dev" | grep -E "result" || true
  sudo smartctl -A "$dev" | awk '
    /Power_On_Hours|Reallocated_Sector_Ct|Current_Pending_Sector|Offline_Uncorrectable|UDMA_CRC_Error_Count/ \
    { printf "  %-28s %s\n", $2, $10 }'
done

echo
echo "Non-zero Reallocated or Current_Pending means treat that drive as untrusted."
echo "High UDMA_CRC usually means a bad SATA cable, not a bad drive."
echo
echo "Start long self-tests with:  sudo smartctl -t long /dev/sdX"
