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

if openshell gateway select "$GATEWAY_NAME" >/dev/null 2>&1; then
  printf 'Selected existing OpenShell gateway: %s\n' "$GATEWAY_NAME"
else
  openshell gateway add --name "$GATEWAY_NAME" --local "$GATEWAY_ENDPOINT"
fi

openshell sandbox list
