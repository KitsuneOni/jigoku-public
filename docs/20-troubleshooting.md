# 20 — Troubleshooting

## Purpose

The things that actually go wrong, and what to check first.

## Triage order

1. Homepage — what is red?
2. `docker compose ps` in the relevant stack
3. `docker compose logs --tail=100 <service>`
4. `df -h /data` — is the pool full?
5. `free -h` — is the box out of memory?

## Playback

**Everything transcodes when it should direct play**
Check the file's subtitle track. PGS image subtitles force burn-in, which
forces a full video transcode. Fix upstream in Bazarr (doc 10) rather than
fighting it in Jellyfin.

**"Playback failed" on the TV only**
Client version drift. The sideloaded Tizen app is pinned; re-sideload it to
match the server version (doc 16).

**Transcoding is software, not NVENC**
```
nvidia-smi
docker exec jellyfin nvidia-smi
```
If the host sees the GPU but the container does not, the NVIDIA Container
Toolkit runtime is not registered — re-run `nvidia-ctk runtime configure` and
restart Docker.

**nvidia-smi reports no devices after a kernel update**
DKMS did not rebuild. `sudo apt install linux-headers-$(uname -r)` then
`sudo dkms autoinstall`. On Debian the headers are not pulled in automatically
the way they are on Ubuntu.

**"No compatible streams" for a few users**
The A400 has no session cap, so this is real GPU saturation or bandwidth, not a
driver limit. Check `nvidia-smi` under load and your upload headroom.

## Storage

**Disk usage doubling**
Hardlinks are failing. Run the doc 04 verification. Usual causes: `/data/media`
and the download folder ended up on different mounts, or "Use Hardlinks" is off
in Radarr/Sonarr.

**Pool full**
```
df -h /data
du -sh /data/media/* | sort -h
```
Then: add a third drive (doc 04), or prune, or add Maintainerr.

**mergerfs did not mount at boot**
Check `x-systemd.requires=/mnt/disk1` is present in the fstab line. Without it
systemd can try to mount the pool before the underlying disks are ready.

## Downloads

**qBittorrent has no connectivity**
Expected if Gluetun is down — that is the kill switch working. `docker compose
logs gluetun`. Usual causes: expired VPN credentials, or the provider changed
server endpoints.

**Torrents connect but never download**
Port forwarding is not applied. Check
`docker exec gluetun cat /tmp/gluetun/forwarded_port` and confirm qBittorrent's
listening port matches.

**SABnzbd unpacking is very slow**
`incomplete` and `complete` are on different filesystems, so the move became a
copy. Both must be inside `/data`.

**Verify the VPN is still working**
```
docker exec qbittorrent curl -s https://ipinfo.io/ip
curl -s https://ipinfo.io/ip
```
Must differ. Run this after any Gluetun update.

## Networking

**Domain does not resolve on the LAN**
AdGuard rewrite missing or enma is down. `dig @192.168.1.11 jellyfin.example.nz`.

**Domain does not resolve remotely**
Tailscale split DNS not configured, or MagicDNS is off.

**Whole house lost internet**
enma is down and it is your only DNS. Set the router back to 1.1.1.1 while you
fix it — this is the tradeoff from doc 13.

**Certificate errors**
```
docker compose logs caddy | grep -i error
```
Usually a rotated or revoked Cloudflare API token.

**A guest can reach something they should not**
Check both layers: the Tailscale ACL and the Caddy `@guests` matcher. Network
ACLs alone do not stop hostname-based access on port 443.

## Containers

**Permission denied on /data**
PUID/PGID mismatch. Everything runs as 1000:1000.
```
ls -la /data
docker exec <service> id
```

**Container restart loop**
```
docker compose logs --tail=200 <service>
```
After an update, check the Renovate PR that bumped it and revert the commit.

**Out of memory**
```
free -h
docker stats --no-stream
```
On 8 GB this is expected under load. Prioritise the RAM upgrade; in the
meantime, avoid running Prometheus (doc 19).

## Backups

**restic fails with a lock error**
```
restic -r <repo> unlock
```
Usually a previous run was killed mid-flight.

**Restore test fails**
Take this seriously — it is the whole point of running it. Check `restic check`
on both repositories, and confirm the SQLite stop-and-snapshot step in
`backup-run.sh` is still working.

## If you ever expose something publicly

This build is Tailscale-only by design. If that changes:

- Install fail2ban or CrowdSec watching Jellyfin auth logs
- Expose **only** Jellyfin — never the *arr apps, which have weak auth and
  plaintext API keys
- Keep Jellyfin patched promptly; it becomes a security obligation
- Note that SSO/forward-auth breaks native Jellyfin clients, so Jellyfin's own
  login is your boundary
