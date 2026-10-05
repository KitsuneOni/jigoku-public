# 14 — Backups

## Purpose

3-2-1 backups of everything irreplaceable. Media is deliberately excluded.

## What is and isn't backed up

| Backed up | Size | Why |
|---|---|---|
| `/opt/appdata/*` | ~740 MiB | Watch history, *arr databases, quality profiles, certs |
| `/opt/repo` | tiny | Already on GitHub, included for completeness |
| **Not** `/data/media` | TBs | Re-downloadable. B2 would cost ~US$60/mo for 10 TB. |

## Prerequisites

- Doc 13 complete (enma running)
- Backblaze account with a private bucket — **`your-jigoku-b2-bucket`** as built

## Steps

### 1. Backblaze

Create a private bucket, then an application key scoped to that bucket with
read+write. The key is shown once.

### 2. Secrets

```
cd /opt/repo
sops secrets/jigoku.enc.yaml
```

```yaml
b2_account_id: "..."
b2_account_key: "..."
restic_password: "..."
```

Generate the restic password properly:

```
openssl rand -base64 32
```

**Put it in your password manager before going further.** Losing it makes both
repositories permanently unreadable. No support ticket fixes this.

### 3. restic and root SSH

```
sudo apt install -y restic
sudo ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""
sudo cat /root/.ssh/id_ed25519.pub
```

Append that to `~/.ssh/authorized_keys` on enma, then **accept the host key for
the exact hostname the script uses**:

```
sudo ssh oni@enma 'echo works'
```

Accepting it for `192.168.1.11` is not enough — the script connects to `enma`,
and an unaccepted host key fails with a confusing SFTP EOF error.

### 4. Initialise both repositories

```
sudo tee /root/.restic-pass > /dev/null <<< 'YOUR_PASSWORD'
sudo chmod 600 /root/.restic-pass

sudo RESTIC_PASSWORD_FILE=/root/.restic-pass \
  restic -r sftp:oni@enma:/srv/restic/jigoku init

sudo B2_ACCOUNT_ID=... B2_ACCOUNT_KEY=... RESTIC_PASSWORD_FILE=/root/.restic-pass \
  restic -r b2:your-jigoku-b2-bucket:jigoku init
```

### 5. The backup script

`scripts/backup-run.sh` triggers the *arr apps' own backup APIs, stops Jellyfin
briefly for SQLite consistency, snapshots to both repos, prunes to retention,
and pushes the result to ntfy.

```
sudo cp /opt/repo/scripts/backup-run.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/backup-run.sh
```

Check the two values that must match your environment:

```
CLOUD_REPO="b2:your-jigoku-b2-bucket:jigoku"
NTFY="http://192.168.1.11:8080/jigoku-backups"
```

**ntfy is `deny-all`, so the notify function needs a token** or backups report
success while alerts silently 401:

```bash
notify() { curl -fsS -H "Authorization: Bearer $NTFY_TOKEN" -d "$1" "$NTFY" >/dev/null 2>&1 || true; }
```

Generate the token on enma:

```
docker exec -it ntfy ntfy token add oni
```

### 6. Environment file

```
sudo tee /root/.backup-env > /dev/null <<'EOF'
B2_ACCOUNT_ID=...
B2_ACCOUNT_KEY=...
NTFY_TOKEN=tk_...
EOF
sudo chmod 600 /root/.backup-env
```

No `export`, no spaces around `=`, no quotes — systemd's `EnvironmentFile` is
fussy.

### 7. Systemd units

Unit files are kept in `config/systemd/` in this repo.

```
[Unit]
Description=restic backup of jigoku configs
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/root/.backup-env
Environment=HOME=/root
Environment=RESTIC_CACHE_DIR=/root/.cache/restic
TimeoutStartSec=3600
ExecStart=/usr/local/bin/backup-run.sh
```

**The `HOME` and `RESTIC_CACHE_DIR` lines are not optional.** systemd runs
services without `$HOME`, so restic cannot find its cache, re-fetches the whole
index from B2 on every run, and over NZ→US latency this hangs indefinitely with
no CPU activity and no error. With the cache set, a run completes in seconds.

Timer at 04:00 — after the 03:00 unattended-upgrades reboot window:

```
[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true
```

```
sudo systemctl daemon-reload
sudo systemctl enable --now jigoku-backup.timer
systemctl list-timers jigoku-backup
```

### 8. Retention

`--keep-daily 7 --keep-weekly 4 --keep-monthly 6`. With deduplication this
settles around 15–40 GB total.

### 9. Restore testing

```
sudo cp /opt/repo/scripts/restore-test.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/restore-test.sh
sudo RESTIC_PASSWORD_FILE=/root/.restic-pass /usr/local/bin/restore-test.sh
```

Restores a canary file, runs a full repository integrity check, pushes the
result to ntfy. **A backup you have never restored is not a backup.**

## Verify

- [ ] `restic snapshots` lists snapshots in both repositories
- [ ] `systemctl start jigoku-backup.service` completes and shows `Deactivated successfully`
- [ ] An ntfy push arrives on your phone
- [ ] `restore-test.sh` reports `no errors were found`
- [ ] The restic password is in your password manager

## Rollback

```
sudo systemctl disable --now jigoku-backup.timer
```

Repositories are append-only in practice — stopping destroys nothing.

## Restoring for real

```
# 1. Rebuild base OS (docs 02–05)
# 2. Restore configs
sudo restic -r b2:your-jigoku-b2-bucket:jigoku restore latest --target /
# 3. Clone the repo, decrypt secrets with the age key from your password manager
# 4. Bring stacks up
```

Media is not restored — Radarr and Sonarr re-acquire it from the library
metadata, which *is* in the backup.

## Notes

### Known warnings, both harmless

`grep: /opt/appdata/bazarr/config.xml: No such file or directory` — Bazarr does
not use that format.

`warn: radarr backup trigger failed` — the script calls
`http://localhost/api/v3/command` but each *arr app listens on its own port.
restic captures the raw SQLite files regardless; only Jellyfin genuinely needs
stopping.

### B2 from New Zealand

First upload of ~520 MiB took about ten minutes: high latency plus many small
pack files with per-request overhead. Subsequent runs only send changed chunks
and complete in seconds — provided the cache environment is set.

### Encryption

restic encrypts client-side. Backblaze only ever holds ciphertext, which
matters given the payload includes every API key you own.
