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

LOOPBACK="$(python3 - "$ORIGIN" <<'PY'
import sys
from urllib.parse import urlsplit

print("1" if urlsplit(sys.argv[1]).hostname in {"127.0.0.1", "localhost", "::1"} else "0")
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

if [[ "$LOOPBACK" == 1 ]]; then
  STATUS_BODY="$(mktemp)"
  trap 'rm -f -- "$STATUS_BODY"' EXIT
  STATUS_CODE="$(curl --silent --show-error --output "$STATUS_BODY" \
    --write-out '%{http_code}' --max-time 10 "$ORIGIN/api/status")" || {
      printf 'Hermes status route: unreachable\n' >&2
      exit 1
    }
  printf 'Hermes status route: HTTP %s\n' "$STATUS_CODE"
  [[ "$STATUS_CODE" == 200 ]] || exit 1
  if ! python3 - "$STATUS_BODY" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    status = json.load(handle)
if status.get("auth_required") is not False:
    providers = ", ".join(status.get("auth_providers") or []) or "none"
    raise SystemExit(
        "ERROR: loopback development mode is not active; "
        f"Hermes requires authentication (providers: {providers})"
    )
PY
  then
    exit 1
  fi

  API_STATUS="$(curl --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --max-time 10 \
    "$ORIGIN/api/plugins/ask-nemoclaw/conversations")" || {
      printf 'Ask NemoClaw API route: unreachable\n' >&2
      exit 1
    }
  printf 'Ask NemoClaw API route: HTTP %s\n' "$API_STATUS"
  if [[ "$API_STATUS" != 200 ]]; then
    printf 'ERROR: the loopback Ask NemoClaw API must return HTTP 200 without a Hermes session\n' >&2
    exit 1
  fi
  printf 'Loopback development connection is ready. No Hermes login is required.\n'
else
  probe 'Ask NemoClaw API route' "$ORIGIN/api/plugins/ask-nemoclaw/conversations"
  printf 'The route responded. Complete authentication in Chrome to verify the signed-in extension session.\n'
fi
