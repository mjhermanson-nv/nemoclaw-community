#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX_NAME="${NEMOCLAW_SANDBOX_NAME:-ask-nemoclaw}"
NEMOCLAW_SOURCE="${NEMOCLAW_SOURCE:-}"

for required_command in docker openshell nemohermes python3; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'Required command is unavailable: %s\n' "$required_command" >&2
    exit 1
  fi
done

DOCKER_DRIVER_STATUS="$(docker info --format '{{json .DriverStatus}}')"
if [[ "$DOCKER_DRIVER_STATUS" == *'io.containerd.snapshotter.v1'* ]]; then
  cat >&2 <<'EOF'
Docker is using the containerd snapshotter, which cannot provide the nested
overlay mounts required by this OpenShell sandbox. Configure Docker to use the
classic overlay2 driver, restart Docker, and rerun this script. See the Brev
host preparation section in README.md for the tested fresh-instance procedure.
EOF
  exit 1
fi

if ! openshell sandbox list >/dev/null; then
  cat >&2 <<'EOF'
The selected OpenShell gateway is unavailable. Start or register the gateway
owned by the deployment, verify that `openshell sandbox list` succeeds, and
rerun this script. The script will not replace an externally supervised gateway.
EOF
  exit 1
fi

if [[ -z "$NEMOCLAW_SOURCE" ]]; then
  if [[ -d "$HOME/.nemoclaw/source/.git" ]]; then
    NEMOCLAW_SOURCE="$HOME/.nemoclaw/source"
  else
    NEMOHERMES_BIN="$(readlink -f "$(command -v nemohermes)")"
    NEMOCLAW_SOURCE="$(CDPATH= cd -- "$(dirname -- "$NEMOHERMES_BIN")/.." && pwd)"
  fi
fi

python3 "$ROOT/scripts/prepare-hermes-image.py" --nemoclaw-source "$NEMOCLAW_SOURCE"

printf 'Sandbox name: %s\n' "$SANDBOX_NAME"
printf 'NemoClaw source: %s\n' "$NEMOCLAW_SOURCE"
# Do not pass --from here. Current generated Hermes images require BuildKit,
# while user-supplied Dockerfiles intentionally remain on the OpenShell
# gateway builder trust boundary. Preparing the installed Hermes source and
# using the normal generated-image path preserves both requirements.
nemohermes onboard \
  --name "$SANDBOX_NAME" \
  "$@"
