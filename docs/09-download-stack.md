# 09 — Download stack

## Purpose

SABnzbd as primary, qBittorrent behind Gluetun as fallback, with a verified
kill switch.

## Prerequisites

- Docs 05, 07 complete
- Usenet provider account (e.g. Eweka, Newshosting, Frugal)
- Usenet indexer account (e.g. NZBGeek, DrunkenSlug, NZBFinder)
- VPN subscription **with port forwarding** — ProtonVPN paid or AirVPN

## Steps

### 1. Secrets

```bash
sops secrets/jigoku.enc.yaml
```

```yaml
vpn_private_key: "..."
vpn_addresses: "10.2.0.2/32"
usenet_host: "news.provider.com"
usenet_user: "..."
usenet_pass: "..."
```

### 2. Gluetun + qBittorrent

qBittorrent has **no network of its own** — it uses Gluetun's network stack via
`network_mode: "service:gluetun"`. If the tunnel drops, qBittorrent loses all
connectivity rather than falling back to your real IP.

```bash
cd /opt/stacks/download
cp .env.example .env && vim .env
docker compose up -d gluetun
docker compose logs -f gluetun    # wait for "healthy"
docker compose up -d qbittorrent
```

**Gluetun must join the `media` network too**, or Radarr and Sonarr cannot
reach qBittorrent's API at `gluetun:8080` and Homepage's widget fails with
`ENOTFOUND gluetun`. This does not weaken the tunnel — qBittorrent still routes
every byte through it via `network_mode: service:gluetun`.

### 3. Verify the kill switch — do not skip

```bash
# What IP does the torrent client see?
docker exec qbittorrent curl -s https://ipinfo.io/ip
# What IP does the host see?
curl -s https://ipinfo.io/ip
```

**These must differ.** The first must be your VPN exit, the second your ISP.
If they match, stop and fix Gluetun before adding a single torrent.

Now test failure:

```bash
docker stop gluetun
docker exec qbittorrent curl -s --max-time 10 https://ipinfo.io/ip
# must fail / time out — NOT return your real IP
docker start gluetun
```

### 4. Port forwarding

ProtonVPN and AirVPN expose a forwarded port. Gluetun writes it to
`/tmp/gluetun/forwarded_port`. The compose file includes a small sidecar that
reads it and updates qBittorrent's listening port via its API on each change.

```bash
docker exec gluetun cat /tmp/gluetun/forwarded_port
```

### 5. qBittorrent config

Login at `https://qbit.example.nz` (default `admin` / check logs for the
temporary password — change it immediately).

Tools → Options:

| Setting | Value |
|---|---|
| Default Save Path | `/data/torrents` |
| Keep incomplete in | `/data/torrents/incomplete` |
| Pre-allocate disk space | ✅ |
| Append .!qB to incomplete | ✅ |
| Global max upload slots | 10 |
| Encryption mode | Require |

### 6. SABnzbd

```bash
docker compose up -d sabnzbd
```

Login at `https://sab.example.nz`, run the wizard.

| Setting | Value |
|---|---|
| Temporary Download Folder | `/data/usenet/incomplete` |
| Completed Download Folder | `/data/usenet/complete` |
| Servers | your provider, SSL on, port 563 |
| Connections | 20–50 (provider-dependent) |

**Both folders must be inside `/data`.** If `incomplete` and `complete` are on
different filesystems, SABnzbd's "move" becomes a full copy and unpacking large
releases takes minutes instead of seconds.

### 7. Unpackerr (optional)

Only needed if your indexers deliver RAR archives. Add later if the *arr apps
start reporting failed imports on archived releases.

## Verify

- [ ] Container IP ≠ host IP
- [ ] Stopping Gluetun kills qBittorrent's connectivity entirely
- [ ] `docker exec gluetun cat /tmp/gluetun/forwarded_port` returns a port
- [ ] SABnzbd test-download completes and lands in `/data/usenet/complete`
- [ ] Files in `/data` are owned by 1000:1000
- [ ] `sudo ss -tlnp` shows neither client bound to 0.0.0.0

## Rollback

```bash
cd /opt/stacks/download && docker compose down
```

In-progress downloads are lost; completed files in `/data` are untouched.

## Notes

### Why Usenet first

No ratio, no seeding obligation, no swarm exposing your IP, and it saturates
your connection rather than depending on peers. On a 1.8 TB pool the absence of
a seeding requirement matters a lot — you can delete watched media freely.

Torrents remain the fallback for anything Usenet doesn't carry, particularly
older and niche content.

### Legal context

Rights holders monitor public torrent swarms and send infringement notices to
ISPs, who forward them to the **account holder** — which may not be you if the
broadband is in someone else's name. New Zealand's Copyright (Infringing File
Sharing) Act 2011 provides for escalation to the Copyright Tribunal. This is
context, not legal advice. It is why the VPN is non-optional for the torrent
path, and part of why Usenet is primary.

### Recreating Gluetun breaks qBittorrent

qBittorrent shares Gluetun's network namespace by container ID. Recreate
Gluetun and a plain `docker restart qbittorrent` fails with a namespace error;
even when it starts, it may have no connectivity until recreated:

```
docker compose up -d --force-recreate qbittorrent
```

Always re-verify the exit IP afterwards.

### SABnzbd rejects unknown hostnames

SABnzbd validates the `Host` header. Reaching it as `sabnzbd` from Radarr, or
as `sab.example.com` through Caddy, returns **403 Forbidden** until each name is
whitelisted — Config → Special → `host_whitelist`, or directly:

```
host_whitelist = sabnzbd, localhost, 192.168.1.10, sab.example.com
```

### If speeds are poor

- Usenet slow → raise connection count, check SSL is on, try a different server
- Torrents slow → check the forwarded port is actually applied in qBittorrent
- Both slow → check Gluetun isn't routing SABnzbd (it shouldn't be; SABnzbd
  runs outside the tunnel by design, since your provider connection is already
  SSL and direct)
