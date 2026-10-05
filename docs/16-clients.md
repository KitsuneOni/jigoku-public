# 16 — Clients

## Purpose

Getting every screen in the house (and a few outside it) playing from jigoku.

## Device matrix

| Device | Client | Tailscale | Notes |
|---|---|---|---|
| Samsung TV (downstairs) | Jellyfin for Tizen | Not needed — LAN | Sideloaded |
| iPhone / iPad | Swiftfin or Infuse | Yes | Infuse direct-plays more |
| Mac | Infuse, Swiftfin, or browser | Yes | |
| Windows PCs | Jellyfin Media Player | Yes | |
| Pop!_OS desktop | Jellyfin Media Player | Yes | |
| Audiobooks, any device | Audiobookshelf app | Yes | |

## Samsung TV — sideloading

The TV is on the LAN, so it reaches jigoku directly and needs no Tailscale.

**Check the Tizen Store first.** Jellyfin became officially available on Tizen
in early 2026, rolling out to newer models first. If it's there, install it and
skip the rest of this section permanently.

### Method: Docker one-liner

Run from your Pop!_OS desktop, not from jigoku.

1. On the TV: **Apps** → type `12345` on the remote → **Developer Mode: On** →
   enter your desktop's IP → restart the TV.

2. From your desktop, on the same subnet:

```bash
docker run --rm ghcr.io/georift/install-jellyfin-tizen 192.168.1.92
```

**No version argument.** Passing one fails with `There is no package with named
Jellyfin-10.10.3.wgt` unless that exact filename exists in the current build
release. The default `Jellyfin.wgt` is what works.

3. Jellyfin appears in the TV's app list. Point it at
   `https://jellyfin.example.nz`.

### Alternative: Apps2Samsung

GUI installer that handles the developer certificate for you. Cross-platform,
and there's an Android app so you can do it from the couch. Same mechanism.

### When Developer Mode misbehaves

On this QN85A the dialog has **no Host PC IP field** — newer firmware dropped
the restriction, so a toggle is all you get. If the dialog appears but will not
enable, or `Device Care` is greyed out, a **forced power-off** clears it: hold
power until the set restarts, or pull the plug for 30 seconds. Standby is not
enough.

Verify the debug port before running the installer:

```
nc -zv 192.168.1.92 26101
```

### Tizen caveats

**Pin the client version to your server version.** The sideloaded app is frozen
at whatever you installed. If Renovate bumps the Jellyfin server and the TV
client drifts behind, you get obscure playback failures. **Re-sideloading is a
checklist item on every Jellyfin major upgrade** — see doc 17.

**It breaks periodically.** Firmware updates can remove the app or turn
Developer Mode off, and the developer certificate expires. That's not a reason
to avoid sideloading; it's the reason the exact command is recorded here, so
redoing it is two minutes rather than an hour of re-research.

**Model year matters.** A 2021+ set runs Tizen 6.0+ and takes the current
build. Older sets need the `10.8.z` branch. `Moonfin` and `Litefin` are lighter
Tizen clients worth trying if stock Jellyfin feels sluggish.

## Apple devices

**Infuse** — paid, and worth it. Direct-plays essentially everything including
TrueHD and DTS-HD, so jigoku streams bytes and the GPU does nothing. Add
Jellyfin as a source via its Jellyfin integration.

**Swiftfin** — free, native, good. Transcodes more often than Infuse.

Either way, install Tailscale first and confirm `https://jellyfin.example.nz`
resolves before configuring the app.

## Windows and Linux

**Jellyfin Media Player** — desktop app built on MPV, handles far more codecs
than the browser and supports direct play properly.

Browser playback works but transcodes more, since browsers support a narrow
codec set.

## Onboarding a remote guest

1. You generate a tagged Tailscale auth key (doc 06, step 6)
2. They install Tailscale and run `tailscale up --authkey=tskey-...`
3. You create their Jellyfin account with downloads disabled (doc 08, step 8)
4. You create their Jellyseerr quota (doc 11, step 2)
5. They install Swiftfin/Infuse/Jellyfin and point it at your domain

Send the auth key through something that isn't SMS.

## Verify

- [ ] TV plays a 1080p file with **no** transcode showing in the Jellyfin dashboard
- [ ] TV plays a 4K HEVC file — direct play over gigabit
- [ ] A file with SRT subtitles direct-plays; the dashboard shows no transcode
- [ ] iPhone over mobile data plays via Tailscale
- [ ] A guest device can reach Jellyfin and **not** Sonarr
- [ ] Watch position syncs between TV and phone

## Rollback

Client-side only. Uninstall and reinstall; nothing on the server changes.

## Notes

### The transcode table

| Situation | Result |
|---|---|
| TV, H.264/HEVC, SRT subs, LAN | Direct play — server idle |
| TV, TrueHD/DTS-HD audio | Audio transcode — cheap |
| **TV, PGS image subtitles** | **Full video transcode — expensive** |
| Remote phone on mobile data | Video transcode to fit bandwidth |
| Mac with Infuse | Direct play nearly always |

Row three is the one to design against, and it's why Bazarr's text-subtitle
preference in doc 10 is load-bearing rather than cosmetic. With no Apple TV in
the house, the Samsung is your primary living-room screen, so this path gets
exercised constantly.

### Why the TV doesn't need Tailscale

It's downstairs on the same LAN. Tailscale solves remote access; the TV never
leaves. If it ever needed remote access, Tizen has no Tailscale client and the
answer would be an Apple TV or Shield instead.
