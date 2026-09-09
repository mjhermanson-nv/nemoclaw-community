#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX_NAME="${NEMOCLAW_SANDBOX_NAME:-browser-context-assistant}"
NEMOCLAW_SOURCE="${NEMOCLAW_SOURCE:-}"

if [[ -z "$NEMOCLAW_SOURCE" ]]; then
  NEMOHERMES_BIN="$(readlink -f "$(command -v nemohermes)")"
  NEMOCLAW_SOURCE="$(CDPATH= cd -- "$(dirname -- "$NEMOHERMES_BIN")/.." && pwd)"
fi

python3 "$ROOT/scripts/prepare-hermes-image.py" --nemoclaw-source "$NEMOCLAW_SOURCE"

printf 'Sandbox name: %s\n' "$SANDBOX_NAME"
printf 'NemoClaw source: %s\n' "$NEMOCLAW_SOURCE"
nemohermes onboard \
  --name "$SANDBOX_NAME" \
  --from "$NEMOCLAW_SOURCE/agents/hermes/Dockerfile"
