# 01 — Hardware prep

## Purpose

Verify the salvaged hardware is trustworthy before building anything on it.
Doing this after you've moved 3 TB of media onto a dying disk is expensive.

## Prerequisites

- Physical access to the Z97 box
- A Linux live USB (any distro) or the existing OS
- 2×8 GB DDR3-1600 if you're doing the RAM upgrade now

## Steps

### 1. RAM upgrade (do this first)

The GA-Z97-D3H has four DDR3 slots and takes 32 GB max. Install the new kit in
slots 1 and 3 (or 2 and 4) for dual channel — check the board manual, they're
usually colour-coded.

```bash
sudo dmidecode -t memory | grep -E "Size|Speed|Locator"
free -h
```

### 2. Test the RAM

Bad RAM corrupts filesystems silently. One full pass minimum, overnight ideally.

```bash
sudo apt install memtest86+
sudo systemctl reboot   # select memtest from GRUB
```

### 3. Audit the drives

This is the important one. These drives are of unknown age.

```bash
sudo apt install smartmontools
lsblk -o NAME,SIZE,MODEL,SERIAL
for d in /dev/sd?; do
  echo "=== $d ==="
  sudo smartctl -i "$d" | grep -E "Model|Serial|Capacity"
  sudo smartctl -A "$d" | grep -E "Power_On_Hours|Reallocated_Sector|Current_Pending|Offline_Uncorrectable|UDMA_CRC"
done
```

Record the results in a table here so you have a baseline:

| Device | Model | Power-on hours | Reallocated | Pending | Verdict |
|---|---|---|---|---|---|
| Seagate ST2000DM001 (2 TB) | Barracuda 7200.14 | 2191 | 0 | 0 | **healthy — in use** |
| WD WD10EADS (1 TB) | Caviar Green | 108380 | 3 | **1453** | **failing — removed** |

The WD drive is out of the build. 1453 pending sectors means the drive has
found that many it cannot reliably read; SMART still reports `PASSED` because
that check only compares against manufacturer thresholds, not trends. Do not
put it back in the pool.

### 4. Long SMART self-test

Takes several hours. Start both in parallel and come back.

```bash
sudo smartctl -t long /dev/sda
sudo smartctl -t long /dev/sdb
# later:
sudo smartctl -l selftest /dev/sda
```

### 5. BIOS settings

- **Restore on AC power loss: ON** — so the box comes back after an outage
- Boot order: OS SSD first
- Disable anything unused (serial, parallel, extra audio)
- Verify VT-d/VT-x enabled (harmless, useful later)

### 6. Physical

- Blow out the dust. A decade of it is normal and it's why the fans are loud.
- Reseat the RTX A400. It needs no power connector — slot power only.
- Confirm the PSU has enough SATA connectors for a third drive later.
- Note free SATA ports on the board — you need at least one spare.

## Verify

- [ ] `free -h` shows the expected RAM total
- [ ] memtest passed one full pass with zero errors
- [ ] Both drives report `Reallocated_Sector_Ct` and `Current_Pending_Sector` at 0
- [ ] Long self-test completed without read failures
- [ ] Baseline table above is filled in

## Rollback

Nothing is destructive here. If RAM fails memtest, pull the new sticks and
test them individually to find the bad one.

## Notes

**Interpreting SMART:** a non-zero `Reallocated_Sector_Ct` isn't automatically
fatal, but a *rising* one is. `Current_Pending_Sector` above zero means the
drive found sectors it can't read — treat that drive as untrusted and don't
put anything on it you're not happy to lose.

**High `UDMA_CRC_Error_Count`** usually means a bad SATA cable, not a bad
drive. Swap the cable and see if it stops incrementing.

Power-on hours above ~40,000 (about 4.5 years of continuous use) means you're
on borrowed time. Plan the replacement drive accordingly. Scrutiny (doc 15)
watches all of this continuously once you're up.
