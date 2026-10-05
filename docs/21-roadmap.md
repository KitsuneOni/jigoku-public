# 21 — Roadmap

What's left to build, in the order it's worth doing. Updated as things land.

## Done

| | |
|---|---|
| 00–17 | Base build: Debian, Docker, mergerfs, Jellyfin, *arr stack, Gluetun, Caddy, Tailscale, AdGuard/DHCP on enma, backups, monitoring |
| 18 | UPS — NUT with the Eaton 5E, clean shutdown on both hosts, ntfy alerts on power events |
| 19 | Prometheus, Grafana, node-exporter, cAdvisor, exportarr |
| — | Authelia SSO with TOTP in front of every admin service |
| — | Radicale CalDAV, DAVx⁵ phone sync, ntfy reminders, dashboard calendar widget |
| — | Resilience: boot services on both hosts, boot notifications, backup failure alerts |

## Next

### 1. Second drive

The weakest point in the build. 1.8 TB with no parity, and a single disk failure loses the
library. Blocked on NZ pricing — compare bare internal drives against shucking a WD Elements
or Seagate Expansion Desktop, and check TradeMe for used enterprise drives.

Six SATA ports are free, so buy the largest that's good value per TB rather than repeating
this in a year.

### 2. Tdarr

Re-encode the 4K library to HEVC. Reclaims 30–50% of the pool and cuts what crosses the
300 Mbps upload when the library is streamed remotely. Uses the A400, runs overnight.

Worth doing before the drive purchase — it may buy enough headroom to wait for a better price.

### 3. Kavita + Suwayomi

Replaces reading manga on ad-laden sites. Suwayomi pulls from the same sources; Kavita serves
them with proper metadata and reading progress synced across devices.

### 4. Forgejo

Self-hosted git. Consolidates projects currently scattered across drives, and gives the
Obsidian vault a second home. GitHub stays as the off-site copy.

### 5. Immich

Replaces Google Photos. Face and object recognition on the A400. Storage-hungry — after the
drive.

## Career track

Purple team, forensics and pentesting. These belong on separate hardware: deliberately
vulnerable software must not run on the machine serving the household's DNS, DHCP and media.

### 6. Second-hand mini PC running Proxmox

The lab host. Isolated network, snapshots before breaking things, Windows and Linux VMs as
needed. Roughly NZ$250–350 used.

### 7. Lab targets

DVWA, Juice Shop, Metasploitable as targets. A Kali VM as the attack box until a dedicated
laptop turns up.

### 8. Velociraptor

Endpoint forensics. Agents on the lab hosts first, then jigoku and enma. Attack from Kali,
hunt with Velociraptor — that loop is the whole point.

### 9. Suricata + CrowdSec

Detection. CrowdSec in front of Caddy for real traffic; Suricata watching the lab network for
the attacks generated against it.

## Housekeeping

- **Uptime Kuma monitors** — anything pointing at `https://*.example.com` now hits the Authelia
  login and reports down. Switch those to direct `IP:port` targets.
- **Credential inventory** — passwords now exist for restic, B2, ntfy, NUT, qBittorrent,
  Radicale, Authelia and Cloudflare. Worth one password-manager entry listing what lives where.
- **Gluetun forwarded port** — qbit-port-sync was removed. If seeding stops working, check
  `docker exec gluetun cat /tmp/gluetun/forwarded_port` and update qBittorrent to match.

## Deliberately not doing

- **Vaultwarden** — Bitwarden already in use.
- **Navidrome** — music isn't listened to locally.
- **AI HAT for the Pi** — the M.2 slot holds the NVMe, and the A400 is better hardware for
  anything AI-shaped.
- **Replacing the family's streaming subscriptions** — that's a conversation, not a project.
