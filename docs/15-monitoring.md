# 15 — Monitoring

## Purpose

Know about problems before they become outages: resource usage, disk health,
and available updates.

## Prerequisites

- Doc 13 complete (Beszel hub, Uptime Kuma and ntfy on enma)

## Steps

### 1. ntfy first — everything routes through it

`https://ntfy.example.com`. The instance is `deny-all`, so users are created
from the CLI on enma:

```
docker exec -it ntfy ntfy user add --role=admin oni
docker exec -it ntfy ntfy access oni "*" rw
```

Quote the `*` or the shell expands it to filenames.

Install the ntfy app and subscribe to `jigoku-alerts`, `jigoku-backups`,
`jigoku-disks`, `jigoku-requests`.

**Credentials belong to the server entry in the app, not the subscription.**
Adding a topic without a saved user for that server produces "user is not
authorized" even when server-side permissions are correct.

For scripts and containers, use a token rather than a password:

```
docker exec -it ntfy ntfy token add oni
```

### 2. Uptime Kuma

`https://uptime.example.com`.

**Settings → Notifications → ntfy:**

| Field | Value |
|---|---|
| Server URL | `http://ntfy` |
| Topic | `jigoku-alerts` |
| Username / Password | your ntfy credentials |
| Default enabled | ✅ |

`http://ntfy` is the container name on the shared compose network. `localhost`
resolves to the Uptime Kuma container itself and will never work.

**Monitors — use IPs, not hostnames.** enma's DNS points at `1.1.1.1`, not at
AdGuard, so it cannot resolve `*.example.com`:

| Name | Type | Target |
|---|---|---|
| jigoku host | Ping | `192.168.1.10` |
| Jellyfin | HTTP(s) | `http://192.168.1.10:8096` |
| Jellyseerr | HTTP(s) | `http://192.168.1.10:5055` |
| SABnzbd | HTTP(s) | `http://192.168.1.10:8090` |
| Internet | Ping | `1.1.1.1` |

Interval 60s, retries 2 — avoids paging on a single blip.

### 3. Beszel — both machines

Hub is on enma. Add each system in the UI, then deploy an agent.

**The same hub public key is used for every agent** — it is not per-system.

On jigoku:

```
cd /opt/stacks/monitoring
cp .env.example .env
nano .env                      # BESZEL_KEY
docker compose up -d beszel-agent
sudo ufw allow from 192.168.1.11 to any port 45876 proto tcp comment 'Beszel agent'
```

On enma, add a `beszel-agent` service with `network_mode: host` to the enma
stack, then:

```
sudo ufw allow from 172.16.0.0/12 to any port 45876 proto tcp comment 'Beszel hub'
sudo ufw allow from 192.168.1.0/24 to any port 45876 proto tcp comment 'Beszel LAN'
docker compose up -d beszel-agent
```

Naming the service explicitly matters on enma — a bare `docker compose up -d`
will recreate AdGuard, and if the file has drifted that takes DNS and DHCP down.

Alerts: CPU > 90% for 10 min, memory > 90%, **disk > 85%**. The disk one is the
warning that tells you to buy the next drive.

### 4. Scrutiny — disk health

```
sudo mkdir -p /opt/appdata/scrutiny/{config,influxdb}
sudo chown -R 1000:1000 /opt/appdata/scrutiny
```

**List only the devices that exist.** As built, jigoku has `/dev/sda` (Seagate
2 TB) and `/dev/sdb` (Samsung SSD). There is no `nvme0` on jigoku — that is
enma's disk.

```
docker compose up -d scrutiny
```

Compare against the doc 01 baseline: Seagate at 2191 power-on hours, zero
reallocated, zero pending. Movement in the last two is the early warning.

Notifications to ntfy topic `jigoku-disks`.

### 5. Diun — update notifications

Diun watches pinned image tags and notifies. It does **not** update anything —
deliberately, since auto-updates mean waking to a broken stack with no record
of what changed.

```yaml
      - DIUN_PROVIDERS_DOCKER_WATCHBYDEFAULT=true
      - DIUN_NOTIF_NTFY_ENDPOINT=http://192.168.1.11:8080
      - DIUN_NOTIF_NTFY_TOPIC=jigoku-alerts
      - DIUN_NOTIF_NTFY_TOKEN=${NTFY_TOKEN}
```

**Without `WATCHBYDEFAULT` it watches nothing** — the default is to track only
containers labelled `diun.enable=true`, and the logs show `No image found` with
`added=0`.

The first run reports every image as "New image found". That is Diun
registering its baseline, not 19 pending updates.

```
docker exec diun diun image list
```

### 6. Alert routing

| Source | Topic | Fires when |
|---|---|---|
| Uptime Kuma | `jigoku-alerts` | A service or host stops responding |
| Beszel | `jigoku-alerts` | CPU/RAM/disk thresholds crossed |
| Scrutiny | `jigoku-disks` | SMART attribute degrades |
| Diun | `jigoku-alerts` | New image version available |
| restic | `jigoku-backups` | Backup succeeds or fails |
| Jellyseerr | `jigoku-requests` | Someone requests something |

Separate topics mean you can mute requests without muting disk failures.

## Verify

- [ ] Beszel graphs both jigoku and enma
- [ ] Scrutiny lists both jigoku disks with SMART data
- [ ] `docker exec diun diun image list` shows all images
- [ ] A test alert from each source reaches your phone
- [ ] Stopping a container triggers an Uptime Kuma alert within a minute

## Rollback

```
cd /opt/stacks/monitoring && docker compose down
```

Purely observational — nothing else depends on it.

## Notes

### Why Beszel and not Prometheus

Prometheus, Grafana, node_exporter and cAdvisor want over a gigabyte of RAM.
Beszel covers the actual need at a few tens of megabytes. Doc 19 has the
Prometheus module ready now that jigoku has 16 GB.

### Alert fatigue

Resist adding monitors for everything. If your phone buzzes ten times a day you
will start ignoring it, and then the one alert that mattered gets ignored too.

### Scrutiny needs privileged device access

It reads SMART directly, so it needs `/dev/sd*` and `SYS_RAWIO`. A genuine
exception to the non-root-container rule — there is no other way to read SMART
attributes.
