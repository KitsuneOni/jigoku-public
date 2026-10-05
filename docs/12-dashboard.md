# 12 — Homepage dashboard

## Purpose

One page showing every service with live status, plus the read-only Docker
socket proxy that makes it safe.

## Prerequisites

- Docs 07 and 10 complete (needs the API keys)

## Steps

### 1. Socket proxy first

Homepage wants the Docker socket for container status. Mounting
`/var/run/docker.sock` into a container gives it root on the host — so we put a
read-only proxy in between that exposes only the container-list endpoint.

```bash
cd /opt/stacks/dashboard
cp .env.example .env
docker compose up -d socket-proxy
docker compose logs socket-proxy
```

The proxy has `CONTAINERS=1` and everything else `0`. `POST=0` means it cannot
start, stop, or create anything even if compromised.

### 2. Collect API keys

| Service | Where |
|---|---|
| Jellyfin | Dashboard → API Keys → New |
| Radarr / Sonarr / Prowlarr / Bazarr | Settings → General → API Key |
| SABnzbd | Config → General → API Key |
| qBittorrent | uses username/password |
| Jellyseerr | Settings → General → API Key |

Store them encrypted:

```bash
sops secrets/homepage.enc.yaml
```

### 3. Deploy

Two environment variables must come from `.env`, not be hardcoded:

```yaml
      - HOMEPAGE_ALLOWED_HOSTS=${HOMEPAGE_ALLOWED_HOSTS}
      - HOMEPAGE_VAR_DOMAIN=${DOMAIN}
```

`HOMEPAGE_ALLOWED_HOSTS` must list every hostname you reach it by, or Homepage
rejects the request outright:

```
HOMEPAGE_ALLOWED_HOSTS=example.com,home.example.com,192.168.1.10:3000
```

`HOMEPAGE_VAR_DOMAIN` is what `services.yaml` interpolates into every link. If
it is unset, every tile points at the literal string
`https://jellyfin.{{homepage_var_domain}}`.

```bash
docker compose up -d homepage
docker exec homepage env | grep -E 'ALLOWED|VAR_DOMAIN'
```

Config lives in [`config/homepage/`](../config/homepage/) and is bind-mounted,
so edits are git commits rather than clicks in a UI.

| File | Contents |
|---|---|
| `settings.yaml` | layout, theme, columns |
| `services.yaml` | every service + widget config |
| `widgets.yaml` | header widgets (resources, search) |
| `docker.yaml` | socket proxy connection |
| `bookmarks.yaml` | links out |

### 4. Layout

Groups as configured:

- **Media** — Jellyfin, Audiobookshelf, Jellyseerr
- **Automation** — Radarr, Sonarr, Prowlarr, Bazarr
- **Downloads** — SABnzbd, qBittorrent
- **Infrastructure** — Dockge, Dozzle, Scrutiny, Beszel
- **enma** — AdGuard, Uptime Kuma, Backrest

### 5. Dockge and Dozzle

```bash
docker compose up -d dockge dozzle
```

**Dockge** reads and writes the actual compose files in `/opt/stacks`, so the
GUI and git stay in sync — unlike Portainer, which keeps its own database and
would silently diverge from this repo.

**Dozzle** is live container logs in a browser tab. Read-only, and it uses the
same socket proxy.

## Verify

- [ ] `https://home.example.nz` loads with all groups
- [ ] Jellyfin widget shows current streams
- [ ] SABnzbd widget shows queue and speed
- [ ] Radarr/Sonarr widgets show counts
- [ ] Disk widget shows the mergerfs pool total, not a single disk
- [ ] `docker exec socket-proxy env | grep POST` returns `POST=0`
- [ ] Dockge lists all stacks and can restart one
- [ ] A `tag:guest` device gets 403 on `home.example.nz`

## Rollback

```bash
cd /opt/stacks/dashboard && docker compose down
```

Pure presentation layer — nothing else depends on it.

## Notes

### Why Homepage rather than Homarr

Homarr's layout lives in its own database. That means it's outside git, needs
separate backup, and can't be code-reviewed or rolled back. Homepage is YAML on
disk: the dashboard is part of this repo, and rebuilding it after a disaster is
`git clone`.

The tradeoff is real — Homarr's drag-and-drop is genuinely nicer to configure.
But it would be the one component breaking the repo-as-source-of-truth model
everything else follows.

### Widget API keys

Homepage reads keys from environment variables referenced in `services.yaml` as
`{{HOMEPAGE_VAR_RADARR_KEY}}`. The values come from `.env`, which is generated
from the SOPS file at deploy time. **No key is ever committed in plaintext.**

### The apex domain

`https://example.com` itself serves Homepage, via a bare-domain block in the
Caddyfile:

```
{$DOMAIN} {
	import internal_only homepage:3000
}
```

This needs an A record for `@` pointing at `192.168.1.10` with Cloudflare's
proxy **off** (grey cloud), and only resolves because AdGuard rewrites it — the
router's DNS rebinding protection discards public-domain answers that point at
private addresses.

### enma services are proxied by IP

Caddy runs on jigoku; enma is a different machine, so its services cannot be
reached by container name:

```
adguard.{$DOMAIN}  → 192.168.1.11:80     # port 80, not 8081, on host networking
uptime.{$DOMAIN}   → 192.168.1.11:3001
ntfy.{$DOMAIN}     → 192.168.1.11:8080
beszel.{$DOMAIN}   → 192.168.1.11:8090
backrest.{$DOMAIN} → 192.168.1.11:9898
```

### Disk widget and mergerfs

Point the disk widget at `/data`, not at `/mnt/disk1`. The mergerfs mount
reports the pool total, which is what you actually care about.
