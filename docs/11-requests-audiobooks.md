# 11 — Jellyseerr and Audiobookshelf

## Purpose

Let the household request titles themselves, with quotas so a 1.8 TB pool
survives contact with enthusiasm. Plus audiobooks.

## Prerequisites

- Docs 08 and 10 complete

## Steps

### 1. Jellyseerr

It needs binding to the Tailscale IP as well as the LAN, or remote users cannot
request anything:

```yaml
    ports:
      - "192.168.1.10:5055:5055"
      - "100.118.227.102:5055:5055"
```

```bash
cd /opt/stacks/arr
docker compose up -d jellyseerr
```

Setup wizard at `https://requests.example.nz`:

1. **Sign in with Jellyfin** — point at `http://jellyfin:8096`. Users log in
   with their existing Jellyfin accounts; no second user list to maintain.
2. Import Jellyfin libraries → select Movies and TV
3. Add Radarr: `http://radarr:7878`, API key, root folder `/data/media/movies`,
   quality profile **Standard**
4. Add Sonarr: `http://sonarr:8989`, root folder `/data/media/tv`

### 2. Quotas — the important bit

Settings → Users → Edit each user:

| Setting | Household | Remote guests |
|---|---|---|
| Auto-approve | ✅ | ❌ |
| Movie quota | 5 per week | 2 per week |
| Series quota | 2 per week | 1 per week |
| Request 4K | ❌ | ❌ |
| Auto-request | ❌ | ❌ |

Without quotas, one person discovering a franchise fills 1.8 TB in a weekend.
With them, it's bounded and you keep approval control over guests.

### 3. Notifications

Settings → Notifications → Webhook (ntfy on enma — configure after doc 13):

```
http://enma:8080/jigoku-requests
```

You get a push when someone requests something; they get one when it's ready.

### 4. Audiobookshelf

```bash
cd /opt/stacks/media
docker compose up -d audiobookshelf
```

At `https://books.example.nz`:

- Create admin account
- Library: **Audiobooks**, path `/data/media/audiobooks`
- Library: **Podcasts**, path `/data/media/podcasts` (optional)
- Metadata provider: Audible

Folder structure it expects:

```
/data/media/audiobooks/
└── Author Name/
    └── Book Title/
        ├── Book Title.m4b
        └── cover.jpg
```

### 5. Audiobookshelf clients

- iOS/Android: official Audiobookshelf app
- Any Subsonic client also works if you prefer

Point them at `https://books.example.nz` over Tailscale.

## Verify

- [ ] Jellyseerr login works with a Jellyfin account, not a separate one
- [ ] A test request appears in Radarr within seconds
- [ ] Quota blocks the 6th request in a week for a quota'd user
- [ ] A guest's request lands in "Pending Approval", not straight through
- [ ] Audiobookshelf scans and shows cover art
- [ ] Playback position syncs between two devices

## Rollback

```bash
docker compose down jellyseerr audiobookshelf
```

Jellyseerr keeps request history in `/opt/appdata/jellyseerr`. Audiobookshelf
keeps progress in `/opt/appdata/audiobookshelf` — neither touches your media.

## Notes

### If the setup wizard's Continue button stays greyed out

The Jellyfin sign-in step can succeed — logs show `Jellyfin Sync Starting` and
`Full Scan Complete` — while the UI refuses to advance. Skip the wizard:

```
docker exec jellyseerr grep -o '"initialized":[^,]*' /app/config/settings.json
```

If it is `false`, stop the container, set it to `true` in
`/opt/appdata/jellyseerr/settings.json`, and start again. Radarr and Sonarr are
then configured normally under Settings → Services.

### Jellyseerr vs adding things yourself

Without it, every request is a text message to you followed by manual entry in
Radarr. With three or four users that becomes a chore quickly. The quota system
is also the only mechanism in the whole stack that bounds growth by *policy*
rather than by you noticing the disk is full.

### 4K requests are off

Deliberately. Guest-requested 4K arrives as large files that then transcode on
a GPU limited to 2–3 sessions. Keep 4K as something you add yourself for the
living-room TV, where it direct-plays over gigabit.

### Audiobooks don't need the *arr stack

Lidarr handles music, not audiobooks, and there's no equivalent for audiobooks
worth running. Add them manually to `/data/media/audiobooks` — Audiobookshelf
handles the metadata lookup itself.
