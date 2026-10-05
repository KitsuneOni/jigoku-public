# 03 — Base hardening

## Purpose

Lock down SSH, firewall the host, and enable automatic security patching —
before anything is exposed to the network.

## Prerequisites

- Doc 02 complete, key-based SSH confirmed working

## Steps

### 1. SSH

**Confirm key auth works before disabling passwords**, or you lock yourself out.

```bash
sudo vim /etc/ssh/sshd_config.d/99-hardening.conf
```

```
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
```

```bash
sudo sshd -t && sudo systemctl restart ssh
```

Keep your existing session open and test a *new* one in another terminal.

### 2. UFW

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'SSH LAN'
sudo ufw allow in on tailscale0 comment 'Tailscale'
sudo ufw allow from 192.168.1.0/24 to any port 8096 proto tcp comment 'Jellyfin LAN (TV)'
sudo ufw enable
sudo ufw status verbose
```

### 3. Unattended upgrades

```bash
sudo apt install -y unattended-upgrades apt-listchanges
sudo dpkg-reconfigure -plow unattended-upgrades
# Debian's origin patterns differ from Ubuntu's — confirm the Debian-Security
# entry is uncommented in Unattended-Upgrade::Origins-Pattern
sudo vim /etc/apt/apt.conf.d/50unattended-upgrades
```

```
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "05:00";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
```

```bash
sudo unattended-upgrade --dry-run --debug
```

### 4. Kernel and sysctl basics

```bash
sudo tee /etc/sysctl.d/99-hardening.conf << 'SYSCTL'
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
fs.protected_hardlinks=1
fs.protected_symlinks=1
SYSCTL
sudo sysctl --system
```

### 5. AppArmor

Enabled by default since Debian 12. Confirm and leave it alone:

```bash
sudo aa-status | head -5
```

If a container misbehaves later, do **not** disable AppArmor as a fix — find
the actual cause.

### 6. Optional audit

```bash
sudo apt install -y lynis
sudo lynis audit system --quick
```

Treat the score as informational. Don't chase 100 — several suggestions are
irrelevant to a home server.

## Verify

- [ ] `ssh -o PreferredAuthentications=password oni@jigoku` is refused
- [ ] `sudo ufw status` shows deny-incoming default and the three rules
- [ ] `sudo unattended-upgrade --dry-run` completes without error
- [ ] `sudo aa-status` reports profiles loaded
- [ ] A fresh SSH session still connects after `systemctl restart ssh`

## Rollback

```bash
sudo rm /etc/ssh/sshd_config.d/99-hardening.conf && sudo systemctl restart ssh
sudo ufw disable
```

If you lock yourself out entirely, you need physical console access — which is
why you test in a second terminal before closing the first.

## Notes

### The UFW/Docker trap

**This is the single most important thing in this document.** Docker writes its
own iptables rules in the `DOCKER-USER` chain, which is evaluated *before* UFW.
A container published as `-p 8096:8096` is reachable from your entire LAN — and
from the internet if the port is ever forwarded — regardless of what UFW says.

Two mitigations, both used in this build:

1. **Bind published ports to a specific interface** in compose, e.g.
   `127.0.0.1:8989:8989` or the Tailscale IP, rather than the default
   `0.0.0.0`. Doc 05 sets this pattern.
2. Only Caddy publishes on all interfaces. Everything else is reached through it.

Verify after any compose change:

```bash
sudo ss -tlnp | grep -v 127.0.0.1
```

Anything listening on `0.0.0.0` that isn't Caddy or Jellyfin needs explaining.

### The Tailscale rule is not optional

Once Tailscale is installed (doc 06), add:

```
sudo ufw allow in on tailscale0 comment 'Tailscale'
```

Without it, tailnet traffic arrives from `100.x.x.x` and is dropped by the
default-deny policy. The symptom is a Jellyfin client reporting "tried 2
candidates for input, unable to reach server" while everything looks correct.

### fail2ban

Deliberately **not** installed. With nothing forwarded and SSH restricted to
the LAN and Tailscale, it has no external traffic to defend against. If you
ever expose Jellyfin publicly, revisit — see doc 20.
