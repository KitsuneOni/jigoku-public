# 02 — Debian 13 install

## Purpose

Clean base OS on the SSD, with the HDDs left completely untouched for doc 04.

## Prerequisites

- Doc 01 complete
- USB stick, 4 GB+
- Debian 13 "Trixie" **netinst** ISO from https://www.debian.org/distrib/
- Your SSH public key ready (generate on your Pop!_OS box if needed):

```
ssh-keygen -t ed25519 -C "oni@pop-os"
cat ~/.ssh/id_ed25519.pub
```

Use the image that includes non-free firmware (the default netinst has done so
since Debian 12). You will need it for the network card and the NVIDIA driver.

## Steps

### 1. Write the ISO

```
sudo dd if=debian-13.x.0-amd64-netinst.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Double-check `/dev/sdX` with `lsblk` first.

### 2. Installer choices

| Prompt | Choose |
|---|---|
| Install type | Install (not graphical, doesn't matter) |
| Hostname | `jigoku` |
| Domain | leave blank, or your local domain |
| Root password | **Leave empty** — see note below |
| Username | `oni` |
| Partitioning | **Manual** |
| Mirror | New Zealand — `ftp.nz.debian.org` |
| Popularity contest | No |
| **Software selection** | Deselect everything except **SSH server** and **standard system utilities** |

**Leaving the root password blank is deliberate.** If you set one, Debian does
not install `sudo` and does not add your user to the sudo group — a classic
Debian-after-Ubuntu trap. Blank root password means the installer sets up sudo
for `oni` the way you expect.

### 3. Partitioning — critical

**Select only the SSD. Do not touch the HDDs.** They get formatted in doc 04
and any mistake here destroys them.

On the SSD:

| Partition | Size | Type | Mount |
|---|---|---|---|
| 1 | 1 GB | EFI System Partition | `/boot/efi` |
| 2 | rest | ext4 | `/` |

Skip LVM — it adds a layer you don't need here. Skip encryption (decision in
doc 00). Debian will warn about no swap partition; a 2 GB swapfile is fine, or
accept none if you have 16 GB+.

### 4. First boot

```
su -
apt update && apt full-upgrade -y
apt install -y sudo curl git vim htop tmux ca-certificates gnupg
usermod -aG sudo oni
exit
```

Log out and back in for the group change to take effect. Then:

```
sudo reboot
```

### 5. Enable contrib, non-free, and non-free-firmware

Needed for the NVIDIA driver in doc 08. Debian 13 uses the deb822 sources
format:

```
sudo vim /etc/apt/sources.list.d/debian.sources
```

Change each `Components:` line to:

```
Components: main contrib non-free non-free-firmware
```

```
sudo apt update
```

### 6. SSH key

```
mkdir -p ~/.ssh && chmod 700 ~/.ssh
vim ~/.ssh/authorized_keys     # paste your public key
chmod 600 ~/.ssh/authorized_keys
```

### 7. Static addressing

Set a **DHCP reservation on the router** rather than a static IP on the host —
it keeps addressing in one place and survives OS reinstalls. Grab the MAC:

```
ip -br link show
```

Reserve something memorable, e.g. `192.168.1.10` for jigoku and
`192.168.1.11` for enma. Record them here:

```
jigoku  192.168.1.__   MAC __:__:__:__:__:__
enma    192.168.1.__   MAC __:__:__:__:__:__
```

### 8. Timezone

```
sudo timedatectl set-timezone Pacific/Auckland
sudo apt install -y systemd-timesyncd
sudo systemctl enable --now systemd-timesyncd
hostnamectl
timedatectl
```

Correct time matters more than it looks — certificate validation, *arr
scheduling, and log correlation all depend on it.

## Verify

- [ ] `ssh oni@192.168.1.10` works from your desktop using the key
- [ ] `sudo -v` works without error (the sudo trap above)
- [ ] `lsblk` shows both HDDs present, unmounted, unformatted
- [ ] `timedatectl` shows NZST/NZDT and NTP synchronised
- [ ] `apt list --upgradable` is empty
- [ ] `apt-cache policy nvidia-driver` shows a candidate (non-free is enabled)
- [ ] The IP matches the router reservation after a reboot

## Rollback

Reinstall. Nothing above this point is worth preserving — that's the point of
doing it before the storage stage.

## Notes

### Why netinst and minimal selection

The netinst image pulls only what you select. Deselecting the desktop
environment gives you a headless system with a few hundred packages instead of
a few thousand — less to patch, fewer CVEs, no suspend behaviour to fight.

### No snaps to avoid

Debian ships no snapd by default, so the Ubuntu-specific warning about the
Docker snap doesn't apply. There is still a wrong package to avoid: Debian's
own `docker.io` in main is older and packaged differently from upstream. Doc 05
uses Docker's official apt repository regardless.

### Debian vs Ubuntu differences you'll hit later

| Thing | Ubuntu | Debian |
|---|---|---|
| GPU driver discovery | `ubuntu-drivers devices` | `nvidia-detect` |
| Driver package | `nvidia-driver-550` | `nvidia-driver` from non-free |
| Non-free repos | enabled by default | must be enabled (step 5) |
| sudo | always configured | only if root password left blank |
| Netplan | yes | no — ifupdown or systemd-networkd |

These are handled where they come up. Nothing later in the build depends on
Ubuntu-specific tooling.
