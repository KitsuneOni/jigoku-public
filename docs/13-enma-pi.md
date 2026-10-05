# 13 — enma (Raspberry Pi 5)

## Purpose

DNS and ad blocking for the whole network, monitoring that survives jigoku
dying, push alerts, and the local backup target.

## Why the SSD, not the SD card

Every service here is write-heavy. AdGuard logs every DNS query. Uptime Kuma
writes to SQLite on every check of every monitor. A restic repository is by
definition a lot of writes.

SD cards die from write wear, and they die **silently** — you find out when a
backup you needed turns out to be corrupt.

**Boot enma from an SSD.** As built: Pi 5 (4 GB) with a 256 GB NVMe on an M.2
HAT, in an enclosure with three fans and a CPU cooler. Idles at 26 °C,
`get_throttled` returns `0x0`.

## Steps

### 1. Flash and first boot

Raspberry Pi Imager → Raspberry Pi OS Lite (64-bit) → write to the NVMe.

In advanced options set the hostname, enable SSH, and add your public key.
**If you forget SSH here you will need a monitor and keyboard** — a fresh
install refuses connections on port 22 otherwise.

Confirm it actually booted from the SSD:

```
findmnt /
```

Root should be on `nvme0n1p2`, not `mmcblk0`.

### 2. Static IP — set this at the console, not over SSH

enma cannot get its address from DHCP once it *is* the DHCP server, and a
router reservation stops meaning anything once the router's DHCP is off.

```
nmcli con show
sudo nmcli con mod "Wired connection 1" \
  ipv4.addresses 192.168.1.11/24 \
  ipv4.gateway 192.168.1.254 \
  ipv4.dns "1.1.1.1,1.0.0.1" \
  ipv4.method manual && sudo nmcli con up "Wired connection 1"
```

The gateway is the router (`.254` on this network, not `.1`).

**enma's own DNS deliberately points at 1.1.1.1, not at itself.** If AdGuard
fails to start you still want the Pi able to resolve names so you can fix it.

```
sudo hostnamectl set-hostname enma
sudo systemctl enable --now ssh
```

### 3. Base setup

```
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y curl git vim htop ufw dnsutils
sudo timedatectl set-timezone Pacific/Auckland
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
docker run --rm hello-world
```

### 4. Firewall — read the DHCP note

```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'SSH LAN'
sudo ufw allow from 192.168.1.0/24 to any port 53 comment 'DNS'
sudo ufw allow from 192.168.1.0/24 to any port 80 proto tcp comment 'AdGuard UI'
sudo ufw allow 67/udp comment 'DHCP server'
sudo ufw allow 68/udp comment 'DHCP client'
sudo ufw enable
```

**Ports 67 and 68 must be unscoped.** A device asking for a lease has no IP
yet — its DISCOVER comes from source `0.0.0.0` to broadcast
`255.255.255.255`, so a rule scoped to `192.168.1.0/24` never matches and
every request is silently dropped. This cost an evening: AdGuard was listening
on 67, the config was correct, and nothing worked.

### 5. Tailscale

```
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --advertise-tags=tag:server
sudo ufw allow in on tailscale0 comment 'Tailscale'
tailscale ip -4
```

Disable key expiry for enma in the admin console.

### 6. Repo and stack

enma needs its own GitHub deploy key — it's a second clone, not the same one:

```
ssh-keygen -t ed25519 -C "enma"
cat ~/.ssh/id_ed25519.pub
```

Add as a deploy key with write access, then:

```
sudo mkdir -p /opt/repo && sudo chown oni:oni /opt/repo
cd /opt && git clone git@github.com:KitsuneOni/jigoku-public.git repo
sudo mkdir -p /opt/appdata /srv/restic
sudo chown -R 1000:1000 /opt/appdata /srv/restic
cd /opt/repo/compose/enma
cp .env.example .env
nano .env          # TZ, DOMAIN, BESZEL_KEY
docker compose up -d
```

### 7. AdGuard — host networking is required

The setup wizard runs on port 3000, then the UI moves to port 80.

**AdGuard must run with `network_mode: host`.** On a Docker bridge it only
sees `172.18.0.2` and cannot serve DHCP at all — clients broadcast to
`255.255.255.255` and those broadcasts never reach a bridged container. The
DHCP settings page will refuse a `192.168.1.x` range as "not in one subnet",
which is the tell.

Settings → DNS settings:

- Upstream: `https://dns.cloudflare.com/dns-query`
- Bootstrap: `1.1.1.1`, `9.9.9.9`

Filters → DNS rewrites — **this is the piece that solves the router problem**:

| Domain | Answer |
|---|---|
| `*.example.com` | `192.168.1.10` |
| `example.com` | `192.168.1.10` |

Verify from another machine before going further:

```
dig @192.168.1.11 jellyfin.example.com +short
```

### 8. DHCP takeover

The SmartModem2 router exposes no way to change the DNS it advertises, so
AdGuard has to serve DHCP or every device needs manual DNS forever.

**Order matters, and AdGuard refuses to enable DHCP while another server is
detected.** Bypass that check via the config file rather than the UI:

```
sudo nano /opt/appdata/adguard/conf/AdGuardHome.yaml
# dhcp: enabled: true
docker restart adguard
sudo ss -ulnp | grep :67       # must show AdGuardHome
```

Then, in this order:

1. **Add jigoku's static lease first** — MAC `74:d4:35:bf:a3:0d` →
   `192.168.1.10`. Without it jigoku pulls a pool address on renewal and
   breaks Caddy, the DNS rewrites and Jellyfin's bindings all at once.
2. Router → Network → LAN → untick **DHCP Server** → Save. **Leave that tab
   open** — re-ticking it is the instant rollback.
3. Confirm `ss -ulnp | grep :67` still shows AdGuard.
4. On a test device: release and renew, check DNS shows `192.168.1.11`.

Do not open AdGuard's DHCP settings page once it is serving — saving it
restarts the server and it has been observed not to come back.

### 9. Patching

enma gets security updates but **no automatic reboot** — a reboot takes DNS
and DHCP down for the whole household:

```
sudo apt install -y unattended-upgrades apt-listchanges
sudo dpkg-reconfigure -plow unattended-upgrades
sudo tee -a /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
```

Check for pending reboots as part of the monthly routine in doc 17.

## Verify

- [ ] `findmnt /` shows the NVMe
- [ ] `dig @192.168.1.11 example.com +short` returns `192.168.1.10` from another host
- [ ] `sudo ss -ulnp | grep :67` shows AdGuardHome
- [ ] A device with no manual DNS config resolves `example.com`
- [ ] jigoku still holds `192.168.1.10` after `systemctl restart networking`
- [ ] `vcgencmd get_throttled` returns `0x0`
- [ ] enma survives a reboot with all services returning

## Rollback

```
# On enma
sudo nano /opt/appdata/adguard/conf/AdGuardHome.yaml   # dhcp: enabled: false
docker restart adguard
```

**Then immediately re-enable DHCP on the router**, or the household has no
addressing.

## Notes

### Why monitoring lives here

If Uptime Kuma ran on jigoku it would go down at exactly the moment you need
it. enma exists so that "jigoku is down" is an alert you receive rather than a
silence you eventually notice.

### The two repos drift

jigoku and enma are separate clones. A change made on one is invisible to the
other until committed and pulled — and a `git pull` on enma will refuse if the
file was edited locally. This has already caused AdGuard's host-networking
change to be silently reverted in enma's working copy. Always commit from
whichever machine you edited, then pull on the other.

### IPv6

Windows prefers IPv6 DNS when the router advertises it, which bypasses an
IPv4-only AdGuard. If a device resolves `example.com` inconsistently, that is
the first thing to check.
