# 18 — UPS with NUT (optional)

## Purpose

Graceful shutdown on power loss. Deferred module — implement when you're ready.

## Why it matters

The obvious argument is protecting the hardware. The real one is **SQLite**.

Jellyfin, Sonarr, Radarr, Prowlarr, Bazarr and Jellyseerr all use SQLite
databases with active write-ahead logs. An unclean shutdown mid-write can
corrupt them. You would restore from backup (doc 14) — but that is an evening
you did not need to spend.

Auckland outages are infrequent but not zero, and brownouts are more common
than full cuts.

## Hardware

A basic 650–850 VA line-interactive unit with USB is enough — you are not
trying to ride out an outage, just to shut down cleanly. Roughly NZ$150–200.

Runtime needed: about two minutes. jigoku idles somewhere around 60–90 W with
the A400 installed (50 W card); enma draws under 10 W.

Check the NUT hardware compatibility list before buying — most CyberPower and
APC units with USB are supported.

## Steps

### 1. Install

```
sudo apt install -y nut nut-client nut-server
lsusb    # confirm the UPS appears
```

### 2. Configure

```
sudo nut-scanner -U   # auto-detect, paste output into ups.conf
sudo vim /etc/nut/ups.conf
```

```
[ups]
    driver = usbhid-ups
    port = auto
    desc = "jigoku UPS"
```

Then:

- `/etc/nut/nut.conf` — `MODE=netserver`
- `/etc/nut/upsd.users` — define a monitor user
- `/etc/nut/upsmon.conf` — `MONITOR ups@localhost 1 upsmon <pass> master`

### 3. Shutdown thresholds

In `upsmon.conf`:

```
SHUTDOWNCMD "/sbin/shutdown -h +0"
FINALDELAY 5
```

Trigger at roughly 40% battery or 3 minutes remaining — enough time for
containers to stop cleanly.

### 4. Ordered shutdown

Stop containers before the host powers off, so SQLite closes cleanly. Point
`NOTIFYCMD` at a script that runs:

```
cd /opt/stacks && for d in */; do (cd "$d" && docker compose stop); done
```

### 5. enma as a NUT client

enma monitors jigoku's UPS over the network and shuts down too:

- `sudo apt install -y nut-client`
- `nut.conf` — `MODE=netclient`
- `upsmon.conf` — `MONITOR ups@192.168.1.10 1 upsmon <pass> slave`

### 6. Alerting

Wire `NOTIFYCMD` to push to ntfy topic `jigoku-alerts` on power loss, so you
know the moment it happens rather than discovering it later.

## Verify

- [ ] `upsc ups@localhost` reports battery charge and load
- [ ] Pulling the wall plug triggers an ntfy alert
- [ ] Running the battery down triggers a clean shutdown
- [ ] Containers stop before the host powers off
- [ ] enma shuts down as well
- [ ] Everything comes back after power is restored (BIOS "restore on AC power
      loss" from doc 01)

## Rollback

```
sudo systemctl disable --now nut-monitor nut-server
sudo apt remove --purge nut nut-client nut-server
```

## Notes

Add the UPS to Uptime Kuma via `upsc` output so battery health appears on the
dashboard alongside everything else.

Replace UPS batteries roughly every 3–5 years. A UPS with a dead battery is
worse than no UPS, because you believe you are protected.
