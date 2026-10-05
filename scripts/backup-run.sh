#!/usr/bin/env bash
# Nightly backup: appdata -> enma (SFTP) and Backblaze B2.
# Media is deliberately excluded — it is re-downloadable (doc 14).
set -euo pipefail

export RESTIC_PASSWORD_FILE=/root/.restic-pass
export B2_ACCOUNT_ID="${B2_ACCOUNT_ID:?set in environment}"
export B2_ACCOUNT_KEY="${B2_ACCOUNT_KEY:?set in environment}"

LOCAL_REPO="sftp:oni@192.168.1.11:/srv/restic/jigoku"
CLOUD_REPO="b2:your-jigoku-b2-bucket:jigoku"
SOURCES="/opt/appdata /opt/repo"
NTFY="http://192.168.1.11:8080/jigoku-backups"
STACKS="/opt/stacks"

notify() { curl -fsS -H "Authorization: Bearer $NTFY_TOKEN" -d "$1" "$NTFY" >/dev/null || echo "warn: notify failed for: $1"; }
fail() {
  notify "❌ jigoku backup FAILED: $1"
  exit 1
}

# 1. Let the *arr apps write their own consistent backup zips.
#    Copying a live SQLite file gives a backup that fails on restore.
for svc in radarr sonarr prowlarr bazarr; do
  docker exec "$svc" curl -fsS -X POST \
    "http://localhost/api/v3/command" \
    -H "X-Api-Key: $(grep -oP '(?<=<ApiKey>)[^<]+' "/opt/appdata/$svc/config.xml")" \
    -d '{"name":"Backup"}' >/dev/null 2>&1 || echo "warn: $svc backup trigger failed"
done

# 2. Jellyfin has no self-backup — stop it briefly for SQLite consistency.
docker stop jellyfin >/dev/null

# shellcheck disable=SC2064
trap "docker start jellyfin >/dev/null" EXIT

# 3. Back up to both repositories.
for repo in "$LOCAL_REPO" "$CLOUD_REPO"; do
  restic -r "$repo" backup $SOURCES \
    --exclude-caches \
    --exclude "/opt/appdata/*/cache" \
    --exclude "/opt/appdata/jellyfin/cache" \
    --tag automated || fail "backup to $repo"

  restic -r "$repo" forget \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 6 \
    --prune || fail "prune on $repo"
done

SIZE=$(restic -r "$LOCAL_REPO" stats latest --mode raw-data 2>/dev/null | grep -i "total size" || echo "size unknown")
notify "✅ jigoku backup OK — $SIZE"
