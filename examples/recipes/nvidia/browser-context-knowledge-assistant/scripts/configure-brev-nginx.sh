#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DASHBOARD_PORT="${NEMOCLAW_DASHBOARD_PORT:-18789}"
NGINX_SITE="${NEMOCLAW_BREV_NGINX_SITE:-/etc/nginx/sites-available/nemoclaw}"
NGINX_SNIPPET="/etc/nginx/snippets/ask-nemoclaw-location.conf"

if ! [[ "$DASHBOARD_PORT" =~ ^[0-9]+$ ]] \
  || (( DASHBOARD_PORT < 1024 || DASHBOARD_PORT > 65535 )); then
  printf 'Invalid NEMOCLAW_DASHBOARD_PORT: %s\n' "$DASHBOARD_PORT" >&2
  exit 2
fi

for required_command in nginx python3 sudo; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'Required command is unavailable: %s\n' "$required_command" >&2
    exit 1
  }
done

sudo test -f "$NGINX_SITE" || {
  printf 'Brev Nginx site not found: %s\n' "$NGINX_SITE" >&2
  exit 1
}

if ! sudo ss -ltn "sport = :$DASHBOARD_PORT" | grep -q LISTEN; then
  printf 'Nothing is listening on Hermes dashboard port %s.\n' "$DASHBOARD_PORT" >&2
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
site_backup="${NGINX_SITE}.ask-nemoclaw-${stamp}.bak"
snippet_backup="${NGINX_SNIPPET}.${stamp}.bak"
sudo cp -a "$NGINX_SITE" "$site_backup"
if sudo test -f "$NGINX_SNIPPET"; then
  sudo cp -a "$NGINX_SNIPPET" "$snippet_backup"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
sed "s/127\\.0\\.0\\.1:18789/127.0.0.1:${DASHBOARD_PORT}/g" \
  "$ROOT/deploy/nginx/ask-nemoclaw-location.conf" \
  > "$tmp_dir/ask-nemoclaw-location.conf"
sudo install -o root -g root -m 0644 \
  "$tmp_dir/ask-nemoclaw-location.conf" "$NGINX_SNIPPET"

sudo python3 - "$NGINX_SITE" "$DASHBOARD_PORT" <<'PY'
from pathlib import Path
import re
import sys

site = Path(sys.argv[1])
port = sys.argv[2]
text = site.read_text(encoding="utf-8")
include = "    include /etc/nginx/snippets/ask-nemoclaw-location.conf;"
if include not in text:
    marker = re.search(r"(?m)^(\s*)location / \{", text)
    if not marker:
        raise SystemExit("Could not find the Nginx root location")
    text = text[:marker.start()] + include + "\n\n" + text[marker.start():]

match = re.search(r"(?ms)^\s*location / \{.*?^\s*\}", text)
if not match:
    raise SystemExit("Could not isolate the Nginx root location")
block = match.group(0)
block, proxy_count = re.subn(
    r"proxy_pass http://127\.0\.0\.1:\d+;",
    f"proxy_pass http://127.0.0.1:{port};",
    block,
    count=1,
)
if proxy_count != 1:
    raise SystemExit("Could not update the Hermes dashboard upstream")
block, host_count = re.subn(
    r"proxy_set_header Host [^;]+;",
    f"proxy_set_header Host 127.0.0.1:{port};",
    block,
    count=1,
)
if host_count != 1:
    raise SystemExit("Could not update the Hermes Host header")
origin = f"proxy_set_header Origin http://127.0.0.1:{port};"
if re.search(r"proxy_set_header Origin [^;]+;", block):
    block = re.sub(r"proxy_set_header Origin [^;]+;", origin, block, count=1)
else:
    block = block.replace(
        f"proxy_set_header Host 127.0.0.1:{port};",
        f"proxy_set_header Host 127.0.0.1:{port};\n        {origin}",
        1,
    )
text = text[:match.start()] + block + text[match.end():]
site.write_text(text, encoding="utf-8")
PY

if ! sudo nginx -t; then
  sudo cp -a "$site_backup" "$NGINX_SITE"
  if sudo test -f "$snippet_backup"; then
    sudo cp -a "$snippet_backup" "$NGINX_SNIPPET"
  else
    sudo rm -f "$NGINX_SNIPPET"
  fi
  printf 'Nginx validation failed; restored the previous configuration.\n' >&2
  exit 1
fi

sudo systemctl reload nginx
printf 'Configured Brev Nginx for Ask NemoClaw on dashboard port %s.\n' "$DASHBOARD_PORT"
printf 'Set the Brev HTTP Secure Link destination port to 80, not %s.\n' "$DASHBOARD_PORT"
printf 'Site backup: %s\n' "$site_backup"
