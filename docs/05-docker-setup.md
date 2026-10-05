# 05 — Docker setup, networks, secrets

## Purpose

Docker from the official apt repo, the three-network segmentation model, and
SOPS for secrets. Everything after this depends on it.

## Prerequisites

- Docs 03 and 04 complete

## Steps

### 1. Install Docker (official apt repo)

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker
docker run --rm hello-world
```

### 2. Log rotation

Without this, container logs fill the SSD eventually.

```bash
sudo tee /etc/docker/daemon.json << 'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "userland-proxy": false
}
JSON
sudo systemctl restart docker
```

### 3. Networks

Three networks, so a compromised download client can't reach your *arr API keys.

```bash
docker network create proxy      # caddy + anything with a web UI
docker network create media      # jellyfin, arr, audiobookshelf
docker network create download   # gluetun, qbittorrent, sabnzbd
```

| Network | Members | Can reach |
|---|---|---|
| `proxy` | caddy, and one leg of each web service | the internet, its members |
| `media` | jellyfin, *arr, jellyseerr, audiobookshelf | each other |
| `download` | gluetun, qbittorrent, sabnzbd | the VPN tunnel only |

The download stack shares `/data` with the media stack by filesystem, not by
network. That's the isolation boundary.

### 4. Directory layout

```bash
sudo mkdir -p /opt/appdata /opt/stacks
sudo chown -R 1000:1000 /opt/appdata /opt/stacks
```

Clone this repo and link the stacks:

```bash
cd /opt && git clone git@github.com:KitsuneOni/jigoku-public.git repo
ln -s /opt/repo/compose/* /opt/stacks/
```

### 5. SOPS and age

```bash
sudo apt install -y age
curl -LO https://github.com/getsops/sops/releases/latest/download/sops-v3.9.0.linux.amd64
sudo mv sops-v3.9.0.linux.amd64 /usr/local/bin/sops && sudo chmod +x /usr/local/bin/sops

mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
grep 'public key' ~/.config/sops/age/keys.txt
```

Put the **public** key in `.sops.yaml`. Put the **private** key in your
password manager — if you lose it, every encrypted secret in the repo is gone.

Encrypt a secrets file:

```bash
sops secrets/jigoku.enc.yaml     # opens $EDITOR, encrypts on save
sops -d secrets/jigoku.enc.yaml  # decrypt to stdout
```

### 6. gitleaks pre-commit hook

```bash
curl -sSfL https://github.com/gitleaks/gitleaks/releases/latest/download/gitleaks_linux_x64.tar.gz | tar xz
sudo mv gitleaks /usr/local/bin/

cat > /opt/repo/.git/hooks/pre-commit << 'HOOK'
#!/usr/bin/env bash
gitleaks protect --staged --config .gitleaks.toml --redact --verbose || {
  echo "gitleaks blocked this commit — a secret was detected."
  exit 1
}
HOOK
chmod +x /opt/repo/.git/hooks/pre-commit
```

## Verify

- [ ] `docker run --rm hello-world` succeeds without sudo
- [ ] `docker network ls` shows proxy, media, download
- [ ] `docker info | grep -i "storage driver"` shows overlay2
- [ ] `sops -d secrets/jigoku.enc.yaml` round-trips
- [ ] Committing a fake API key is blocked by the pre-commit hook
- [ ] `sudo ss -tlnp | grep -v 127.0.0.1` shows nothing unexpected

## Rollback

```bash
sudo apt remove --purge docker-ce docker-ce-cli containerd.io
sudo rm -rf /var/lib/docker
```

## Notes

### Never mount the Docker socket

`/var/run/docker.sock` is root on the host. A container with it mounted can
start a privileged container and own the machine. Homepage and Dockge both
*want* it — doc 12 puts a read-only socket proxy in between instead, exposing
only the container-list endpoint.

### PUID/PGID

Every LinuxServer image takes `PUID`/`PGID`. Setting them to `1000:1000` means
files created by containers are owned by your user and readable across the
stack. Mismatched IDs are the cause of roughly every "permission denied" in
self-hosting.

### Pinned tags

Images are pinned to versions, never `:latest`. Renovate (doc 17) opens a PR
per update, so every change is reviewable and revertible via git. `:latest`
means an unattended `docker compose pull` can break your stack with no record
of what changed.
