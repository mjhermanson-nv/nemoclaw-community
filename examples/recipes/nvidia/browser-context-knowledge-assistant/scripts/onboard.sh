#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX_NAME="${NEMOCLAW_SANDBOX_NAME:-ask-nemoclaw}"
NEMOCLAW_SOURCE="${NEMOCLAW_SOURCE:-}"

if [[ -z "$NEMOCLAW_SOURCE" ]]; then
  if [[ -d "$HOME/.nemoclaw/source/.git" ]]; then
    NEMOCLAW_SOURCE="$HOME/.nemoclaw/source"
  else
    NEMOHERMES_BIN="$(readlink -f "$(command -v nemohermes)")"
    NEMOCLAW_SOURCE="$(CDPATH= cd -- "$(dirname -- "$NEMOHERMES_BIN")/.." && pwd)"
  fi
fi

python3 "$ROOT/scripts/prepare-hermes-image.py" --nemoclaw-source "$NEMOCLAW_SOURCE"

# NemoClaw uses the directory containing --from as the Docker build context.
# The managed Hermes Dockerfile copies repository-root paths such as tools/ and
# agents/, so place the prepared Dockerfile at the repository root.
CUSTOM_DOCKERFILE="$NEMOCLAW_SOURCE/Dockerfile.ask-nemoclaw"
cp "$NEMOCLAW_SOURCE/agents/hermes/Dockerfile" "$CUSTOM_DOCKERFILE"

printf 'Sandbox name: %s\n' "$SANDBOX_NAME"
printf 'NemoClaw source: %s\n' "$NEMOCLAW_SOURCE"
printf 'Custom Dockerfile: %s\n' "$CUSTOM_DOCKERFILE"
nemohermes onboard \
  --name "$SANDBOX_NAME" \
  --from "$CUSTOM_DOCKERFILE"
