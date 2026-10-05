#!/usr/bin/env bash
source /etc/nut/ntfy-token
curl -fsS -H "Authorization: Bearer $NTFY_TOKEN" \
  -d "UPS: $1" http://192.168.1.11:8080/jigoku-alerts >/dev/null || logger -t nut-notify "notify failed: $1"
