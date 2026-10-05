# 08 — Jellyfin with NVENC (RTX A400)

## Purpose

Media server with GPU transcoding, and the subtitle policy that keeps the
Samsung TV from hammering the encoder.

## Prerequisites

- Docs 05, 06, 07 complete
- NVIDIA RTX A400 physically installed and visible to `lspci`

## Hardware notes

The A400 is Ampere (GA107), 4 GB GDDR6, 50 W, single-slot, **no supplementary
power connector** — it draws everything through the PCIe slot.

Three things this buys you over the GTX 760 it replaced:

| | GTX 760 (Kepler) | RTX A400 (Ampere) |
|---|---|---|
| Driver branch | 470 legacy, DKMS fights modern kernels | current `nvidia-driver` |
| HEVC encode | **none** — H.264 only | 8-bit and 10-bit |
| NVENC session cap | 2–3 (GeForce driver limit) | **none** — pro card |

That last row matters more than it looks: professional cards are not subject to
the driver-imposed concurrent-session cap that GeForce cards are. There is no
`nvidia-patch` step in this build, and nothing to re-apply after driver updates.

AV1 **decode** is supported; AV1 **encode** is not (that arrived with Ada).
Decode is the half that matters for playback, so this is a non-issue here.

## Steps

### 1. Confirm the card is seen

```bash
lspci | grep -i nvidia
```

Expect a line naming the A400. If nothing prints, reseat the card before going
further.

### 2. Kernel headers first — do not skip

Debian does not pull headers in automatically the way Ubuntu does. Without
them the DKMS build fails silently and you reboot to a black screen.

```bash
sudo apt install -y linux-headers-$(uname -r)
```

### 3. Install the driver from Debian non-free

Ampere is current silicon, so the standard packaged driver is correct — no
legacy branch, and no reason to use NVIDIA's own repo.

```bash
sudo apt install -y nvidia-detect
nvidia-detect                      # confirms the recommended package name
sudo apt install -y nvidia-driver firmware-misc-nonfree
sudo reboot
```

After reboot:

```bash
nvidia-smi
```

This must print a table showing the A400, a driver version, and a temperature
before you continue. If it reports no devices:

```bash
lsmod | grep nouveau      # should be empty — nouveau must be blacklisted
dkms status               # should show the nvidia module built for your kernel
```

### 4. NVIDIA Container Toolkit

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

That last command must print the GPU table **from inside a container**. If the
host sees the card but the container does not, the runtime is not registered —
re-run `nvidia-ctk runtime configure` and restart Docker.

### 5. Deploy

```bash
cd /opt/stacks/media
cp .env.example .env && nano .env
sudo chown -R 1000:1000 /opt/appdata/jellyfin
docker compose up -d jellyfin
```

**Create and chown the appdata directory first.** Docker creates bind-mount
paths as root, and Jellyfin then crashes in a restart loop with
`Access to the path '/config/log' is denied`.

Bind to the Tailscale IP as well as the LAN, or remote clients connect to a
port nothing is listening on:

```yaml
    ports:
      - "${LAN_IP}:8096:8096"
      - "100.118.227.102:8096:8096"
```

Both entries under **one** `ports:` key — a second block is a YAML error.

### 6. First-run wizard

Browse to `https://jellyfin.example.nz`.

- Admin account: **not** your daily-viewing account. Separate strong password.
- Libraries:

| Library | Type | Path |
|---|---|---|
| Movies | Movies | `/data/media/movies` |
| TV | Shows | `/data/media/tv` |
| Music | Music | `/data/media/music` |

- Metadata language: English, country New Zealand
- **Do not** enable the built-in remote access / UPnP port mapping

### 6b. LAN networks

Dashboard → Networking → **LAN Networks** → add `100.64.0.0/10`.

Without it Jellyfin treats every Tailscale client as internet-remote and applies
remote bitrate caps, so you transcode unnecessarily for yourself and anyone
sharing the server.

### 7. Hardware acceleration

Dashboard → Playback → Transcoding:

- Hardware acceleration: **NVIDIA NVENC**
- Enable decoding for: H264, HEVC, VC1, **AV1**
- **Enable hardware encoding: on**
- Enable Tone mapping: on
- Allow encoding in HEVC format: on

AV1 decode is ticked deliberately — the A400 handles it, and so does your
2021+ Samsung TV.

### 8. Subtitle policy — still load-bearing

Dashboard → Playback:

- **Burn in subtitles: Only image-based subtitles** (default; verify it)

The A400 has far more encode headroom than the old card, but burn-in still
forces a full video transcode where none was needed. The real fix stays
upstream: doc 10 configures Bazarr and quality profiles to prefer text
subtitles so image subtitles rarely arrive at all.

### 9. Users

One account per person, never shared:

| Setting | Guests |
|---|---|
| Allow media playback | ✅ |
| Allow audio/video transcoding | ✅ |
| Allow media downloads | ❌ |
| Allow deletion | ❌ |
| Manage server | ❌ |

### 10. Plugins

Dashboard → Plugins → Catalogue:

- **Intro Skipper** — fingerprints and skips TV intros
- **Playback Reporting** — usage stats, feeds Homepage

## Verify

- [ ] `nvidia-smi` on the host shows the A400
- [ ] `nvidia-smi` inside a container shows the same
- [ ] Play a file and confirm Dashboard shows "Transcoding (NVENC)" not "(SW)"
- [ ] `nvidia-smi` during playback shows a process and non-zero encoder usage
- [ ] Direct play works from the LAN with no transcode at all
- [ ] `docker exec jellyfin ls /data/media` succeeds
- [ ] Guest account cannot see Dashboard

## Rollback

```bash
cd /opt/stacks/media && docker compose down jellyfin
```

Config persists in `/opt/appdata/jellyfin`, so bringing it back up restores
users and watch history.

To back out the driver itself:

```bash
sudo apt remove --purge nvidia-driver nvidia-kernel-dkms
sudo reboot
```

## Notes

### Transcode scratch space

Jellyfin writes transcode segments to disk. The compose file points this at
`/transcode` backed by tmpfs — faster, and saves SSD write cycles. It is capped
at 2 GB in the committed file; with 16 GB of RAM installed you can raise that if
large 4K transcodes ever fail for space.

### What actually causes transcoding

| Situation | Result |
|---|---|
| Samsung TV, H.264/HEVC/AV1, text subs, LAN | **Direct play** — server idle |
| Samsung TV, TrueHD/DTS-HD audio | Audio transcode only — cheap |
| Samsung TV, PGS image subtitles | **Full video transcode** |
| Remote iPhone on mobile data | Video transcode to fit bandwidth |
| Mac with Infuse | Direct play almost always |

Row three is the one to design against — hence doc 10's subtitle rules.

### Version drift with the Tizen client

The sideloaded TV client bundles its own web client. A client a full minor
version ahead of the server fails with **no server-side log entries at all** —
the client never reaches the playback endpoints. If the TV shows a generic
error and `docker logs jellyfin` shows nothing during ten attempts, that is the
cause. Match the versions.

### Concurrent streams

No artificial session cap applies to this card, so the practical ceiling is GPU
throughput and upload bandwidth rather than a driver limit. At 100–500 Mbps up
and a 50 W Ampere encoder, a handful of simultaneous 1080p transcodes is
comfortable. Watch `nvidia-smi` under real load rather than guessing.
