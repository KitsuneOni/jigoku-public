# 00 — Overview and decisions

## Purpose

Why this is built the way it is. Read once; skim later when you've forgotten
why something is odd.

## Architecture

```
                    Internet
                       │
                  [ router ]  ── DHCP reservations for jigoku + enma
                       │
        ┌──────────────┴──────────────┐
        │                             │
   [ jigoku ]                     [ enma ]
   Debian 13 (Trixie)             Pi OS (Pi 5)
   Docker                         Docker
   ├─ caddy      (443)            ├─ adguard       (53)
   ├─ jellyfin                    ├─ uptime-kuma
   ├─ audiobookshelf              ├─ ntfy
   ├─ sabnzbd                     ├─ beszel-hub
   ├─ gluetun → qbittorrent       └─ backrest  ← restic repo
   ├─ prowlarr/radarr/sonarr/bazarr
   ├─ jellyseerr
   ├─ homepage + socket-proxy
   └─ beszel-agent, scrutiny, diun

   Tailscale on both. No inbound ports forwarded.
```

## Decisions and why

| Decision | Reason |
|---|---|
| Debian 13 (Trixie) | Minimal by default, no snapd, same base as Pi OS on enma. |
| Docker for everything | Reproducible, all config in git, one service can't break another. |
| Docker from official apt repo | Debian's own `docker.io` is older and packaged differently. |
| mergerfs, no parity | Media is re-downloadable. On one disk parity is meaningless; the pool exists so drives can be added without rebuilding. |
| SnapRAID later, not now | mergerfs → mergerfs+SnapRAID is additive. No migration needed. |
| Usenet primary | No ratio, no seeding, no swarm, saturates the line. Fits limited disk. |
| qBittorrent behind Gluetun | Fallback for what Usenet lacks. Kill switch, never leaks. |
| Tailscale only, nothing forwarded | Every client except the TV runs Tailscale; the TV is on the LAN. |
| Domain + Caddy | One URL that resolves correctly at home *and* remotely. See doc 07. |
| Homepage over Homarr | YAML in git. Homarr's state lives in its own DB, outside version control. |
| NVENC over Quick Sync | Haswell iGPU can't encode HEVC. The A400 can, including 10-bit. |
| RTX A400 over a GeForce card | Pro cards have no NVENC session cap — no `nvidia-patch`, nothing to re-apply after driver updates. |
| Debian's packaged `nvidia-driver` | Ampere is current silicon; no legacy branch needed. |
| No LUKS | Protects only against physical theft, at the cost of every unattended reboot. |
| Beszel over Prometheus | Lighter and enough. Prometheus (doc 19) is unblocked by the 16 GB kit whenever you want it. |

## Known constraints

- **16 GB RAM** (Transcend 2×8 GB, inbound). Two DDR3 slots stay free, so 32 GB
  later is a second identical kit. Prometheus (doc 19) becomes viable at 16 GB.
- **1.8 TB usable**, one drive. The WD 1 TB was pulled — SMART showed 1453
  pending sectors at 108k power-on hours. mergerfs runs fine on a single disk;
  adding drives later is one fstab line, no rebuild.
- **RTX A400 (Ampere)**: HEVC 8/10-bit encode, AV1 decode, no AV1 encode,
  no session cap.
- **Samsung Tizen is the primary living-room client** and cannot overlay PGS
  image subtitles — those force a full transcode. Text subtitles are enforced
  as policy in docs 08 and 10, not left to chance.

## Conventions

- Container config lives in `/opt/appdata/<service>/`
- Media and downloads live in `/data/` (the mergerfs pool)
- Compose files live in this repo, symlinked or deployed to `/opt/stacks/`
- Every service runs as UID/GID 1000, never root
- Image tags are pinned; Renovate opens PRs to bump them
