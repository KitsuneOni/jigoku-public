# jigoku

Home media server and homelab. Two machines, everything in Docker, everything in git.

Both hosts run Debian — `jigoku` on Debian 13 (Trixie), `enma` on Raspberry Pi OS,
which is Debian-based. Same package manager, same conventions, one set of habits.

| Host | Hardware | Role |
|---|---|---|
| `jigoku` | Gigabyte GA-Z97-D3H, i7 Haswell, RTX A400, gigabit wired | Media, downloads, automation |
| `enma` | Raspberry Pi 5, 4 GB, 256 GB NVMe | DNS, DHCP, monitoring, alerts, backup target |

## Stack

**Media** — Jellyfin (NVENC), Audiobookshelf

**Automation** — Prowlarr, Radarr, Sonarr, Bazarr, Recyclarr, Jellyseerr

**Downloads** — SABnzbd (primary), qBittorrent behind Gluetun (fallback)

**Access** — Tailscale for remote, Caddy + Let's Encrypt via Cloudflare DNS-01

**Auth** — Authelia SSO with TOTP in front of every admin service

**Network** — AdGuard Home on `enma` serving DNS and DHCP for the LAN

**Calendar** — Radicale (CalDAV), DAVx⁵ phone sync, reminders pushed to ntfy

**Dashboard** — Homepage, served at `https://example.com`

**Ops** — restic + Backrest → `enma` and Backblaze B2, Beszel, Scrutiny, Diun, Dockge, Dozzle

**Metrics** — Prometheus, Grafana, node-exporter, cAdvisor, exportarr

**Power** — NUT with an Eaton 5E, clean shutdown on both hosts

**Alerts** — Uptime Kuma + ntfy, pushed to phone

## Access model

Admin services require LAN or Tailscale **plus** Authelia login **plus** TOTP.

Jellyfin, Jellyseerr, Audiobookshelf, Radicale and ntfy deliberately bypass Authelia —
their TV, mobile and CalDAV clients cannot follow an auth redirect. They keep their own
authentication and remain LAN/Tailscale only.

## Build order

Work through `docs/` in order. Stages 00–08 leave you with a working Jellyfin
server on their own; everything after is additive. Each doc has the same shape:

**Purpose → Prerequisites → Steps → Verify → Rollback → Notes**

| # | Doc | Status |
|---|---|---|
| 00 | [Overview and decisions](docs/00-overview.md) | ✅ |
| 01 | [Hardware prep](docs/01-hardware-prep.md) | ✅ |
| 02 | [Debian install](docs/02-debian-install.md) | ✅ |
| 03 | [Base hardening](docs/03-base-hardening.md) | ✅ |
| 04 | [Storage and mergerfs](docs/04-storage-mergerfs.md) | ✅ |
| 05 | [Docker setup](docs/05-docker-setup.md) | ✅ |
| 06 | [Tailscale](docs/06-tailscale.md) | ✅ |
| 07 | [Domain, DNS, Caddy](docs/07-domain-dns-caddy.md) | ✅ |
| 08 | [Jellyfin](docs/08-jellyfin.md) | ✅ |
| 09 | [Download stack](docs/09-download-stack.md) | ✅ |
| 10 | [*arr stack](docs/10-arr-stack.md) | ✅ |
| 11 | [Requests and audiobooks](docs/11-requests-audiobooks.md) | ✅ |
| 12 | [Dashboard](docs/12-dashboard.md) | ✅ |
| 13 | [enma (Pi 5)](docs/13-enma-pi.md) | ✅ |
| 14 | [Backups](docs/14-backups.md) | ✅ |
| 15 | [Monitoring](docs/15-monitoring.md) | ✅ |
| 16 | [Clients](docs/16-clients.md) | ✅ |
| 17 | [Maintenance](docs/17-maintenance.md) | ✅ |
| 18 | [UPS](docs/18-ups-optional.md) | ✅ |
| 19 | [Prometheus](docs/19-prometheus-optional.md) | ✅ |
| 20 | [Troubleshooting](docs/20-troubleshooting.md) | reference |
| 21 | [Roadmap](docs/21-roadmap.md) | reference |

Docs 20 and 21 are references, not stages.

### Added after the numbered build

| | Status |
|---|---|
| Authelia SSO with TOTP | ✅ |
| Radicale calendar + ntfy reminders + dashboard widget | ✅ |
| Boot services so every stack comes up after a restart | ✅ |
| Backup failure notifications on both hosts | ✅ |
| `enma` backing itself up to its own local and B2 repos | ✅ |

## Shopping list

| Item | Status | Rough cost |
|---|---|---|
| UPS (Eaton 5E Gen 2) | ✅ Bought and wired | — |
| Large HDD (8–16 TB) | **Next** — 1.8 TB fills fast at 4K | NZ$300–650 |
| Mini PC for an isolated security lab | Planned | NZ$250–350 |

### Running costs

| | |
|---|---|
| Domain `example.com` | ~NZ$25/yr |
| Newshosting + NZBGeek | ~NZ$100/yr |
| Proton VPN | ~NZ$8/mo |
| Backblaze B2 | <NZ$1/mo |

## Current state

| | |
|---|---|
| jigoku | Debian 13, 16 GB RAM, RTX A400, 1.8 TB pool (Seagate 2 TB) |
| enma | Pi 5 4 GB, 256 GB NVMe in a Pironman 5, static `192.168.1.11` |
| Domain | `example.com`, Cloudflare DNS, Caddy with Let's Encrypt |
| Auth | Authelia, file backend, TOTP enrolled |
| DNS/DHCP | AdGuard on enma serves the whole LAN |
| Backups | jigoku → enma + B2 `your-jigoku-b2-bucket` at 04:00; enma → local + B2 `your-enma-b2-bucket` at 03:30 |
| Power | NUT, ~60 min runtime at current load, graceful shutdown on both hosts |
| Remote | Tailscale, tailnet `your-tailnet.ts.net` |
| Clients | Sideloaded Tizen on the Samsung TV, Jellyfin apps on mobile, DAVx⁵ for calendar |

**Known constraint:** 1.8 TB on a single drive with no parity. Media is
re-downloadable by design, but a second drive is one fstab line away — see
doc 04.

## Secrets

Nothing sensitive is committed in plaintext. `.env` files are gitignored;
`secrets/*.enc.yaml` are SOPS-encrypted with age. gitleaks runs pre-commit and
in CI. See [docs/05](docs/05-docker-setup.md#sops).

**The age private key and the restic password are not in this repo and cannot
be. Store both in a password manager.** Losing the restic password makes every
backup permanently unrecoverable.
