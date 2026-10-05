#!/usr/bin/env bash
source /root/.enma-backup-env
COUNT=$(docker ps -q | wc -l)
curl -fsS -H "Authorization: Bearer $NTFY_TOKEN" \
  -d "$(hostname) booted — $COUNT containers up, kernel $(uname -r)" \
  http://localhost:8080/jigoku-alerts >/dev/null || logger -t boot-notify "notify failed"
