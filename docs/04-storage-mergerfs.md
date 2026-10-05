# 04 — Storage and mergerfs

## Purpose

Pool the media disk(s) into one `/data` path with a layout that makes hardlinks
work. Get this wrong and every completed download is *copied* instead of
linked, doubling disk usage and breaking seeding.

## Current state

**One drive in the pool: the Seagate ST2000DM001 (2 TB).**

The WD WD10EADS (1 TB) was removed after the doc 01 audit — 1453 pending
sectors at 108,380 power-on hours. It is not in this build.

mergerfs on a single disk is not a workaround; it's the point. The pool exists
now so that adding a second drive later is one fstab line and `mount -a`, with
no migration, no rebuild, and nothing in the *arr config to change.

## Prerequisites

- Doc 03 complete
- Seagate passed SMART in doc 01 (0 reallocated, 0 pending)

## Steps

### 1. Identify the disk

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINT
```

Match the serial against your doc 01 table. **Be certain which device is the
2 TB Seagate** — the next step destroys data. The OS SSD is a separate device
and must not be touched.

Note the Seagate still carries an old NTFS partition. Confirm nothing on it is
wanted before continuing.

### 2. Partition and format

```bash
sudo parted /dev/sdX --script mklabel gpt
sudo parted /dev/sdX --script mkpart primary ext4 0% 100%
sudo mkfs.ext4 -m 0 -L disk1 /dev/sdX1
```

Substitute the real device from step 1. `-m 0` reclaims the 5% root reserve —
pointless on a media disk, and that's ~100 GB back on 2 TB.

### 3. Mount points

```bash
sudo mkdir -p /mnt/disk1 /data
sudo blkid /dev/sdX1        # note the UUID
```

### 4. fstab

```bash
sudo vim /etc/fstab
```

```
UUID=<disk1-uuid>  /mnt/disk1  ext4  defaults,noatime  0 2

/mnt/disk*  /data  fuse.mergerfs  defaults,nonempty,allow_other,use_ino,cache.files=partial,dropcacheonclose=true,category.create=mfs,minfreespace=50G,fsname=mergerfs,x-systemd.requires=/mnt/disk1  0 0
```

```bash
sudo apt install -y mergerfs
sudo systemctl daemon-reload
sudo mount -a
df -h /data
```

`/data` should report ~1.8 TB.

### 5. Directory layout

This structure is not arbitrary — it's what makes hardlinks and atomic moves
work. Everything lives under one mount point.

```bash
sudo mkdir -p /data/torrents/{movies,tv,music}
sudo mkdir -p /data/usenet/{incomplete,complete}
sudo mkdir -p /data/media/{movies,tv,music,audiobooks}
sudo chown -R 1000:1000 /data
sudo chmod -R 775 /data
```

### 6. Verify hardlinks actually work

**Do not skip this.** It's the whole point of the stage.

```bash
echo test > /data/torrents/movies/testfile
ln /data/torrents/movies/testfile /data/media/movies/testlink
stat -c '%i %h %n' /data/torrents/movies/testfile /data/media/movies/testlink
```

Both must show the **same inode number** and a link count of **2**. If the
inodes differ, mergerfs made a copy — stop and fix the mount options.

```bash
rm /data/torrents/movies/testfile /data/media/movies/testlink
```

## Verify

- [ ] `df -h /data` shows ~1.8 TB
- [ ] `mount | grep mergerfs` shows the expected options
- [ ] Hardlink test passes with matching inodes
- [ ] `ls -la /data` shows ownership `1000:1000`
- [ ] After `sudo reboot`, `/data` mounts automatically

## Rollback

```bash
sudo umount /data
# remove the mergerfs line from /etc/fstab
```

The underlying disk keeps a normal ext4 filesystem and stays readable at
`/mnt/disk1` — a deliberate property of mergerfs, and the reason it beats RAID
here.

## Notes

### Living on 1.8 TB

That's roughly 100–150 solid 1080p films, or a couple of series plus a handful
of 4K WEB-DLs. Enough to build the system and prove it works, which is the
right first goal. Doc 10's quality profiles and size caps exist to slow the
fill rate; Beszel (doc 15) alerts at 85% so you get warning before it bites.

### Adding a drive later

1. Format and mount it at `/mnt/disk2`
2. Add the fstab line
3. `sudo mount -a`

The `/mnt/disk*` glob picks it up. Nothing else changes — not the *arr root
folders, not Jellyfin's libraries, not the compose files. This is why parity
was deferred rather than designed out.

### Why the create policy matters

`category.create=mfs` means "most free space" — with one disk it's a no-op, but
it's correct from the moment a second disk appears. `minfreespace=50G` stops
writes to a disk that's nearly full.

**Hardlinks cannot cross filesystems.** Because `/data/torrents`, `/data/usenet`
and `/data/media` all live inside the same pool, links resolve on the same
underlying disk. This is exactly why the whole tree sits under one mount point
rather than separate `/downloads` and `/media` mounts.

### Adding SnapRAID later

Dedicate a drive as parity (must be ≥ the largest data drive), install
`snapraid`, schedule `snapraid sync` nightly. Nothing above changes.
