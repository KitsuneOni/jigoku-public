#!/usr/bin/env bash
# Monthly restore verification. A backup you have never restored is not a backup.
set -euo pipefail

export RESTIC_PASSWORD_FILE=/root/.restic-pass
REPO="sftp:oni@enma:/srv/restic/jigoku"
SCRATCH="/tmp/restore-test-$$"
NTFY="http://enma:8080/jigoku-backups"
CANARY="opt/appdata/radarr/config.xml"

notify() { curl -fsS -d "$1" "$NTFY" >/dev/null 2>&1 || true; }

cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

mkdir -p "$SCRATCH"

if ! restic -r "$REPO" restore latest --target "$SCRATCH" --include "/$CANARY"; then
  notify "❌ RESTORE TEST FAILED — restic restore errored"
  exit 1
fi

if [ ! -s "$SCRATCH/$CANARY" ]; then
  notify "❌ RESTORE TEST FAILED — canary file missing or empty"
  exit 1
fi

if ! restic -r "$REPO" check; then
  notify "❌ RESTORE TEST FAILED — repository check failed"
  exit 1
fi

notify "✅ Restore test passed — canary restored, repo integrity OK"
