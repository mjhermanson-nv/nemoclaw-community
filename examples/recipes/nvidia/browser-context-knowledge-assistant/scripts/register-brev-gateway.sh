#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

GATEWAY_NAME="${NEMOCLAW_GATEWAY_NAME:-nemoclaw}"
GATEWAY_ENDPOINT="${NEMOCLAW_GATEWAY_ENDPOINT:-https://127.0.0.1:8080}"
MANAGEMENT_ENV="/etc/nemoclaw/gateway-management.env"

if [[ "$(systemctl is-active openshell-gateway.service 2>/dev/null || true)" != active ]]; then
  printf 'The Brev-owned openshell-gateway.service is not active.\n' >&2
  exit 1
fi

if [[ ! -r "$MANAGEMENT_ENV" ]]; then
  printf 'The Brev gateway declaration is unavailable: %s\n' "$MANAGEMENT_ENV" >&2
  exit 1
fi

# The launchable owns this file. It contains paths and gateway settings, not
# inference credentials. Export its values only to the child OpenShell calls.
set -a
# shellcheck disable=SC1091
. "$MANAGEMENT_ENV"
set +a

if [[ -z "${OPENSHELL_LOCAL_TLS_DIR:-}" || ! -r "$OPENSHELL_LOCAL_TLS_DIR/ca.crt" ]]; then
  printf 'The declared Brev gateway TLS directory is incomplete.\n' >&2
  exit 1
fi

system_version="$(/usr/local/bin/openshell-gateway --version 2>&1 | head -1 || true)"
user_gateway="$(dirname "$(command -v openshell)")/openshell-gateway"
user_version="$($user_gateway --version 2>&1 | head -1 || true)"
if [[ -z "$system_version" || -z "$user_version" || "$system_version" != "$user_version" ]]; then
  printf 'Refusing to register mismatched OpenShell versions.\n' >&2
  printf 'Brev-owned gateway: %s\n' "${system_version:-unavailable}" >&2
  printf 'Updated gateway:    %s\n' "${user_version:-unavailable}" >&2
  printf 'Use a refreshed, version-compatible NemoClaw launchable.\n' >&2
  exit 1
fi

if openshell gateway list 2>/dev/null | awk -v name="$GATEWAY_NAME" '$1 == "-" && $2 == name { found=1 } $1 == name { found=1 } END { exit !found }'; then
  openshell gateway select "$GATEWAY_NAME"
else
  openshell gateway add --name "$GATEWAY_NAME" --local "$GATEWAY_ENDPOINT"
fi

openshell sandbox list
