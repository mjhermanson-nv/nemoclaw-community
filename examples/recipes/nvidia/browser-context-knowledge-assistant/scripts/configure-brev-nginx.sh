#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DASHBOARD_PORT="${NEMOCLAW_DASHBOARD_PORT:-18789}"
PROXY_PORT="${NEMOCLAW_BREV_PROXY_PORT:-18889}"
NGINX_CONFIG="${NEMOCLAW_BREV_NGINX_CONFIG:-/etc/nginx/conf.d/ask-nemoclaw-dashboard.conf}"

for value_name in DASHBOARD_PORT PROXY_PORT; do
  value="${!value_name}"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || (( value < 1024 || value > 65535 )); then
    printf 'Invalid %s: %s\n' "$value_name" "$value" >&2
    exit 2
  fi
done

if [[ "$DASHBOARD_PORT" == "$PROXY_PORT" ]]; then
  printf 'The Hermes dashboard and Brev proxy ports must be different.\n' >&2
  exit 2
fi

for required_command in nginx sed sudo; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'Required command is unavailable: %s\n' "$required_command" >&2
    exit 1
  }
done

if ! sudo -n ss -ltn "sport = :$DASHBOARD_PORT" | grep -q LISTEN; then
  printf 'Nothing is listening on Hermes dashboard port %s.\n' "$DASHBOARD_PORT" >&2
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
config_backup="${NGINX_CONFIG}.${stamp}.bak"
had_config=false
if sudo -n test -f "$NGINX_CONFIG"; then
  had_config=true
  sudo -n cp -a "$NGINX_CONFIG" "$config_backup"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
sed \
  -e "s/__DASHBOARD_PORT__/${DASHBOARD_PORT}/g" \
  -e "s/__PROXY_PORT__/${PROXY_PORT}/g" \
  "$ROOT/deploy/nginx/ask-nemoclaw-server.conf" \
  > "$tmp_dir/ask-nemoclaw-dashboard.conf"
sudo -n install -o root -g root -m 0644 \
  "$tmp_dir/ask-nemoclaw-dashboard.conf" "$NGINX_CONFIG"

if ! sudo -n nginx -t; then
  if [[ "$had_config" == true ]]; then
    sudo -n cp -a "$config_backup" "$NGINX_CONFIG"
  else
    sudo -n rm -f "$NGINX_CONFIG"
  fi
  printf 'Nginx validation failed; restored the previous configuration.\n' >&2
  exit 1
fi

sudo -n systemctl reload nginx
printf 'Configured the Ask NemoClaw Brev proxy on port %s for Hermes port %s.\n' \
  "$PROXY_PORT" "$DASHBOARD_PORT"
printf 'Create a separate Brev HTTP Secure Link with destination port %s.\n' "$PROXY_PORT"
if [[ "$had_config" == true ]]; then
  printf 'Config backup: %s\n' "$config_backup"
fi
