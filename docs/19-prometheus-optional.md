# 19 — Prometheus and Grafana (optional)

## Purpose

Replace or supplement Beszel with the full observability stack. Unblocked once
the 16 GB kit is installed.

## Prerequisites

- 16 GB+ RAM in jigoku — **satisfied** once the Transcend kit is installed
- Doc 15 complete

## Why this is deferred

Prometheus, Grafana, node_exporter and cAdvisor together want somewhere north
of 1 GB of RAM. That was unaffordable on 8 GB; with the 16 GB kit installed it
is comfortable, and this module is unblocked.

Beszel covers the operational need. This module exists because Prometheus is
the stack worth knowing professionally, the dashboards are genuinely useful,
and it is a good portfolio piece — not because Beszel is failing you.

## Components

| Component | Role |
|---|---|
| Prometheus | Time-series database, scrapes metrics |
| Grafana | Dashboards and alerting |
| node_exporter | Host metrics (CPU, RAM, disk, network) |
| cAdvisor | Per-container resource usage |
| exportarr | Sonarr/Radarr/Prowlarr queue and library metrics |
| smartctl_exporter | Disk SMART as metrics (complements Scrutiny) |

## Steps

### 1. Deploy

```
cd /opt/stacks/monitoring
docker compose -f docker-compose.prometheus.yml up -d
```

### 2. Prometheus targets

`config/prometheus/prometheus.yml` scrapes node_exporter, cAdvisor, exportarr
instances and smartctl_exporter at 30s intervals. Retention set to 30 days —
longer than that on this hardware is not worth the disk.

### 3. Grafana

`https://grafana.example.nz`. Add Prometheus as a datasource at
`http://prometheus:9090`.

Import these dashboard IDs to start:

| ID | Dashboard |
|---|---|
| 1860 | Node Exporter Full |
| 193 | Docker / cAdvisor |
| 15757 | Docker container overview |

Then build your own — the *arr queue depth and Jellyfin stream count panels are
the ones you will actually look at.

### 4. Alerting

Grafana → Alerting → Contact points → Webhook → ntfy topic `jigoku-alerts`.

Useful alerts:

- Disk usage above 85% (the one that matters most on this pool)
- Any container restart loop
- Jellyfin transcode sessions at the NVENC limit
- SABnzbd queue stalled for over an hour

### 5. Decide about Beszel

Both can coexist — Beszel is light enough that it costs nothing to keep as a
simple at-a-glance view. Or remove it once Grafana is doing the job.

## Verify

- [ ] Prometheus targets page shows all scrapes UP
- [ ] Grafana renders the Node Exporter dashboard with live data
- [ ] cAdvisor shows per-container memory
- [ ] A test alert reaches ntfy
- [ ] `free -h` still shows meaningful headroom under load

## Rollback

```
docker compose -f docker-compose.prometheus.yml down -v
```

Beszel keeps running throughout, so you are never without monitoring.

## Notes

Watch retention and cardinality. Prometheus disk usage grows with the number of
distinct label combinations, not just time. If it balloons, cut the scrape
interval to 60s and retention to 15 days before blaming the hardware.
