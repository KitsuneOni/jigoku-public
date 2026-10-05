#!/usr/bin/env bash
set -euo pipefail
export RESTIC_PASSWORD_FILE=/root/.restic-pass
export B2_ACCOUNT_ID="${B2_ACCOUNT_ID:?set in environment}"
export B2_ACCOUNT_KEY="${B2_ACCOUNT_KEY:?set in environment}"

LOCAL_REPO="/srv/restic/enma"
CLOUD_REPO="b2:your-enma-b2-bucket:enma"
SOURCES="/opt/appdata /opt/repo"
NTFY="http://localhost:8080/jigoku-backups"

notify() { curl -fsS -H "Authorization: Bearer $NTFY_TOKEN" -d "$1" "$NTFY" >/dev/null || echo "warn: notify failed for: $1"; }
fail() { notify "enma backup FAILED: $1"; exit 1; }

for repo in "$LOCAL_REPO" "$CLOUD_REPO"; do
  restic -r "$repo" backup $SOURCES --exclude-caches --tag automated || fail "backup to $repo"
  restic -r "$repo" forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune || fail "prune on $repo"
done

notify "enma backup OK"
