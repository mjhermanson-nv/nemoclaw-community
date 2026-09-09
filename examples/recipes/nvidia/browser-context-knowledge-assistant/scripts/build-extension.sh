#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES_ORIGIN="${1:-http://127.0.0.1:18789}"

python3 "$ROOT/scripts/configure-extension.py" \
  --hermes-origin "$HERMES_ORIGIN" \
  --output "$ROOT/build/extension"

printf '%s\n' "Load this directory with chrome://extensions -> Load unpacked:"
printf '%s\n' "$ROOT/build/extension"
