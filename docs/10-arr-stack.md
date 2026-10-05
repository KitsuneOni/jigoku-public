# 10 — The *arr stack

## Purpose

Automate acquisition, naming, and import — with quality profiles that fit a
1.8 TB pool and an RTX A400.

## Prerequisites

- Docs 08 and 09 complete

## Order matters

Deploy and configure in this order: **Prowlarr → Radarr/Sonarr → Bazarr →
Recyclarr**. Each depends on the previous.

## Steps

### 1. Deploy

```bash
cd /opt/stacks/arr
cp .env.example .env && vim .env
docker compose up -d
```

### 2. Prowlarr

`https://prowlarr.example.nz`. Settings → General → set authentication to
**Forms** with a strong password (Prowlarr's auth is weak — it's Tailscale-only
for a reason).

**Indexers** → add your Usenet indexer(s) and any torrent indexers.

**Apps** → add Radarr and Sonarr. Prowlarr pushes indexer config to both, so
you configure indexers exactly once.

| Field | Value |
|---|---|
| Prowlarr Server | `http://prowlarr:9696` |
| Radarr Server | `http://radarr:7878` |
| API Key | from Radarr → Settings → General |

### 3. Radarr

`https://radarr.example.nz`.

**Media Management:**

| Setting | Value |
|---|---|
| Rename Movies | ✅ |
| Movie Format | `{Movie CleanTitle} ({Release Year}) [imdbid-{ImdbId}] - {Quality Full}` |
| Movie Folder Format | `{Movie CleanTitle} ({Release Year})` |
| **Use Hardlinks instead of Copy** | ✅ **critical** |
| Root Folder | `/data/media/movies` |

**Download Clients:** add SABnzbd (`sabnzbd:8080`) and qBittorrent
(`gluetun:8080` — qBittorrent is reachable at Gluetun's hostname because it
shares that network namespace).

**SABnzbd will return 403 Forbidden on the first test.** It validates the
`Host` header, and `sabnzbd` is not whitelisted by default. Add it in SABnzbd
under Config → Special → `host_whitelist`. No restart needed.

### 4. Sonarr

Same pattern. Root folder `/data/media/tv`, hardlinks on.

| Setting | Value |
|---|---|
| Series Folder Format | `{Series TitleYear} [imdbid-{ImdbId}]` |
| Season Folder Format | `Season {season:00}` |
| Episode Format | `{Series TitleYear} - S{season:00}E{episode:00} - {Episode CleanTitle} [{Quality Full}]` |

### 5. Verify hardlinks in practice

After the first successful import:

```bash
find /data -samefile "/data/media/movies/<Some Movie (2024)>/<file>.mkv"
```

Two paths should be listed — one under `torrents`/`usenet`, one under `media`.
If only one, hardlinking failed and you're burning double the disk. Revisit
doc 04.

### 6. Quality profiles — sized for your constraints

This is where the storage and GPU limits become policy rather than hope.

**Radarr → Settings → Profiles:**

| Profile | Allowed | Notes |
|---|---|---|
| Standard | Bluray-1080p, WEBDL-1080p, WEBRip-1080p | Default for everything |
| 4K Light | WEBDL-2160p only | **No remuxes** — 15–25 GB not 60–80 GB |

**Settings → Quality** — set size limits:

| Quality | Max size (MB/min) |
|---|---|
| WEBDL-1080p | 60 |
| Bluray-1080p | 90 |
| WEBDL-2160p | 180 |

**As built: 4K allowed, remuxes blocked.** A 4K WEB-DL is 15–25 GB where a
remux is 60–120 GB, and on a 65" panel the difference is not visible. Untick
**Remux-2160p and Remux-1080p** in the profile, and check **Upgrade Until** is
not set to a remux quality — otherwise Radarr keeps hunting upgrades toward it.

Size caps are the belt-and-braces half, since a mislabelled release can still
slip through:

| Quality | Max (MB/min) |
|---|---|
| WEBDL-2160p | 180 |
| Bluray-2160p | 200 |
| WEBDL-1080p | 60 |
| Bluray-1080p | 90 |

**Sonarr needs the same edits.** A season multiplies everything — three 4K
seasons of one show is 200–300 GB, a sixth of the pool.

**Custom formats to block:**

- `x265 (no HDR)` at 1080p — poor client compatibility for marginal savings

AV1 is **not** blocked. The A400 decodes it in hardware and the 2021+ Samsung
TV plays it natively, so AV1 releases are usually smaller files that still
direct-play. (The A400 cannot *encode* AV1, but encoding is only needed when
transcoding, and AV1 sources rarely need it here.)

### 7. Recyclarr

Syncs TRaSH-Guides quality definitions and custom formats automatically rather
than you maintaining them by hand.

```bash
docker compose up -d recyclarr
docker exec recyclarr recyclarr sync
```

Config at `config/recyclarr/recyclarr.yml`. It runs daily via the container's
own schedule.

### 8. Bazarr — the subtitle policy

`https://bazarr.example.nz`. Connect to Radarr and Sonarr.

**Settings → Languages** → English, and create a profile:

| Setting | Value |
|---|---|
| Subtitle type | **Normal (text)** |
| Providers | OpenSubtitles.com, Podnapisi, Subscene |
| Upgrade subtitles | ✅ |

**This is load-bearing.** The Samsung TV cannot overlay PGS image subtitles, so
Jellyfin burns them in — which forces a full 4K HEVC transcode on a GPU that
struggles with exactly that. Bazarr fetching clean SRT files means the TV
direct-plays instead.

## Verify

- [ ] Prowlarr shows all indexers green under Test All
- [ ] Radarr and Sonarr each list both download clients as healthy
- [ ] A test movie downloads, imports, renames, and appears in Jellyfin
- [ ] `find -samefile` shows two paths for the imported file
- [ ] Bazarr fetches an `.srt` alongside the video
- [ ] `docker exec recyclarr recyclarr sync` completes cleanly
- [ ] Disk usage after import ≈ file size, not double

## Rollback

```bash
cd /opt/stacks/arr && docker compose down
```

Config in `/opt/appdata/{prowlarr,radarr,sonarr,bazarr}` persists. Media already
imported is untouched — the *arr apps only manage metadata and file placement.

## Notes

### API keys

Each *arr app has a 32-character API key stored in plaintext in its config.
They're in `.gitignore` and matched by a gitleaks rule. This is the main reason
these services are Tailscale-only and guests are ACL-restricted away from them.

### Storage pressure

With 1.8 TB against a 6–12 TB appetite, you will fill this pool. The size
limits above slow it down; they don't prevent it. Options when it happens:

1. Add a second drive (one fstab line — doc 04)
2. Add Maintainerr to auto-remove unwatched media
3. Manually prune via Radarr/Sonarr

### Dead releases

A release that downloads only `.par2` files has had its content articles taken
down — common for 4K studio catalogue titles. Radarr reports **"No video files
were found in the selected folder"** on manual import.

Fix: delete from Activity → Queue with **Blocklist Release** ticked, then
search again. Radarr picks a different release immediately. Without the
blocklist tick it grabs the same dead NZB next time.

### Don't add both Usenet and torrent versions

Prowlarr feeds both source types to Radarr, which picks the best result by
score. It won't grab both. If you see duplicates, check for two indexers
serving the same content and adjust priorities.
