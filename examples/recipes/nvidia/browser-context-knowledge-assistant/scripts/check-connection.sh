#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

ORIGIN="${1:-}"
[ -n "$ORIGIN" ] || {
  printf 'Usage: %s HERMES_ORIGIN\n' "$0" >&2
  exit 2
}

ORIGIN="$(python3 - "$ORIGIN" <<'PY'
import sys
from urllib.parse import urlsplit

value = sys.argv[1]
parsed = urlsplit(value)
loopback = parsed.hostname in {"127.0.0.1", "localhost", "::1"}
valid_scheme = parsed.scheme == "https" or (parsed.scheme == "http" and loopback)
if (
    not valid_scheme
    or not parsed.hostname
    or parsed.username
    or parsed.password
    or parsed.query
    or parsed.fragment
    or parsed.path not in {"", "/"}
):
    raise SystemExit("ERROR: use an exact HTTPS origin or an HTTP loopback origin")
try:
    parsed.port
except ValueError as error:
    raise SystemExit(f"ERROR: invalid origin port: {error}")
print(f"{parsed.scheme}://{parsed.netloc}")
PY
)"
probe() {
  local label url status
  label="$1"
  url="$2"
  status="$(curl --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --max-time 10 "$url")" || {
      printf '%s: unreachable\n' "$label"
      return 1
    }
  printf '%s: HTTP %s\n' "$label" "$status"
  case "$status" in
    200|302|401|403) return 0 ;;
    *) return 1 ;;
  esac
}

probe 'Hermes dashboard route' "$ORIGIN/"
probe 'Ask NemoClaw API route' "$ORIGIN/api/plugins/ask-nemoclaw/conversations"
printf 'The route responded. Complete authentication in Chrome to verify the signed-in extension session.\n'
