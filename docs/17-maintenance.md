# 17 — Maintenance

## Purpose

The routine. What to do weekly, monthly, and when something updates.

## The two-repo rule

jigoku and enma are **separate clones** of this repository. A change made on
one is invisible to the other until committed and pushed, and `git pull` on the
second machine refuses if the file was edited locally.

This has already silently reverted AdGuard's `network_mode: host` in enma's
working copy, which would have taken DNS and DHCP down for the household on the
next `docker compose up -d`.

**Rule: edit in one place, commit, push, pull on the other.** Never edit the
same file on both.

Before any `docker compose up -d` on enma, check:

```
grep -A6 "adguard:" /opt/repo/compose/enma/docker-compose.yml
```

It must show `network_mode: host` and no `ports:` block. And prefer naming the
service — `docker compose up -d beszel-agent` — so a drifted file cannot
recreate AdGuard by accident.

## Renovate

Enable the Renovate GitHub App on `KitsuneOni/jigoku-public`. Config in
`renovate.json`. It opens a PR whenever a pinned image tag has a newer version,
so every update is reviewable and revertible.

Diun tells you an update exists; Renovate turns it into a commit. Both are
notification-only — nothing updates itself.

## Update runbook

```
cd /opt/repo && git pull
cd /opt/stacks/<stack>
docker compose pull
docker compose up -d
docker compose logs -f --tail=50
```

If it breaks:

```
cd /opt/repo && git revert <commit> && git push
docker compose up -d
```

Because tags are pinned in git, reverting the commit reverts the version.

## Weekly

- [ ] Glance at `https://example.com` — everything green?
- [ ] Disk usage. Above 85%? Time to plan the next drive.
- [ ] Skim Uptime Kuma for flapping services
- [ ] Review Jellyseerr pending requests
- [ ] Check for failed *arr imports (Activity → Queue). A release that
      downloads only `.par2` files is dead — delete it and tick
      **Blocklist Release**, then Radarr grabs a working one immediately.

## Monthly

- [ ] Review and merge Renovate PRs
- [ ] Check Scrutiny against the doc 01 baseline — any attribute moving?
- [ ] Confirm `restore-test.sh` passed
- [ ] `sudo apt update && sudo apt full-upgrade` on **both** machines
- [ ] **enma: check for a pending reboot** — it patches automatically but never
      reboots itself, by design

```
ls /var/run/reboot-required 2>/dev/null && echo "REBOOT PENDING"
```

Reboot enma deliberately, at a time when the household losing DNS and DHCP for
a minute is fine.

- [ ] Start a long SMART self-test: `sudo smartctl -t long /dev/sda`
- [ ] Review Tailscale for devices you no longer recognise

## Quarterly

- [ ] `restic check --read-data-subset=10%` on both repositories
- [ ] Review Jellyfin users — remove anyone who has stopped using it
- [ ] Rotate the Cloudflare API token and the B2 application key
- [ ] Test a real restore of one service from backup
- [ ] Review AdGuard's query log for anything odd on the network

## After a Jellyfin server upgrade

**Re-sideload the TV client.** The Tizen app is pinned at whatever version was
installed and drifts out of API compatibility silently — the symptom is
playback failing with no log entries at all on the server side.

```
docker run --rm ghcr.io/georift/install-jellyfin-tizen 192.168.1.92
```

No version argument — passing one fails unless that exact filename exists in
the current build release. Developer Mode must be on, and if the dialog
misbehaves, a **forced power-off** of the TV clears it.

Renovate labels Jellyfin PRs `needs-tv-resideload`.

## After an NVIDIA driver or kernel update

No `nvidia-patch` step — the RTX A400 is a pro card with no session cap. What
does need checking is that DKMS rebuilt:

```
nvidia-smi
dkms status
```

If `nvidia-smi` reports no devices after a kernel bump:

```
sudo apt install -y linux-headers-$(uname -r)
sudo dkms autoinstall
```

## After recreating Gluetun

qBittorrent shares Gluetun's network namespace, so its reference goes stale
whenever Gluetun's container ID changes:

```
docker compose up -d --force-recreate qbittorrent
docker exec qbittorrent curl -s --max-time 10 https://ipinfo.io/ip
```

Must return a Netherlands IP. A plain `docker restart` fails with a namespace
error.

## After adding a drive

1. Format, mount at `/mnt/disk2` (doc 04)
2. Add the fstab line
3. `sudo mount -a && df -h /data`

The `/mnt/disk*` glob picks it up. Nothing else changes.

## Reboot windows

| Machine | Behaviour |
|---|---|
| jigoku | unattended-upgrades, automatic reboot **03:00 NZST** |
| enma | patches automatically, **never reboots itself** |

03:00 NZST is mid-afternoon UK time, chosen so it does not land in your
sister's evening viewing. The backup timer at 04:00 sits after it.

## Notes

### What not to automate

Watchtower-style auto-updates are deliberately absent. The failure mode is
discovering at 9pm that the media server broke overnight for reasons you cannot
reconstruct. Diun plus Renovate gives the same information with a human
decision in the middle.

### Update discipline

Update one stack at a time and verify before moving on. The *arr apps
occasionally ship breaking database migrations. Backups run at 04:00 — update
after that, not before.

Jellyfin's 10.10 → 10.11 upgrade consolidated `library.db` into `jellyfin.db`.
It went cleanly on a small library, but take a manual copy of
`/opt/appdata/jellyfin` before any major version jump regardless.
