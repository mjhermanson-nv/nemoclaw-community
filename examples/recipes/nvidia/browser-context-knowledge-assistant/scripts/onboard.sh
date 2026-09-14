#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX_NAME="${NEMOCLAW_SANDBOX_NAME:-ask-nemoclaw}"
NEMOCLAW_SOURCE="${NEMOCLAW_SOURCE:-}"

# The Brev launchable may retain older system binaries after the maintained
# installer places current binaries under ~/.local/bin. Prefer the current
# user-local installation explicitly instead of depending on shell PATH order.
NEMOHERMES_BIN="${NEMOHERMES_BIN:-$HOME/.local/bin/nemohermes}"
OPENSHELL_BIN="${OPENSHELL_BIN:-$HOME/.local/bin/openshell}"
[[ -x "$NEMOHERMES_BIN" ]] || NEMOHERMES_BIN="$(command -v nemohermes || true)"
[[ -x "$OPENSHELL_BIN" ]] || OPENSHELL_BIN="$(command -v openshell || true)"

# Current NemoClaw requires a current OpenShell gateway for provider and
# inference-route configuration. On the tested Ubuntu 22.04 Brev launchable,
# the image-owned gateway is older and the native current binary exceeds the
# host glibc level. After prepare-brev-gateway.sh performs the explicit
# lifecycle handoff, select NemoClaw-managed mode and its documented,
# authenticated compatibility container.
GATEWAY_WILL_START=0
if [[ -r /etc/nemoclaw/gateway-management.env ]]; then
  if [[ "$(systemctl is-active openshell-gateway.service 2>/dev/null || true)" == active ]]; then
    cat >&2 <<'EOF'
The legacy Brev OpenShell gateway is still active. Run
`bash scripts/prepare-brev-gateway.sh` before onboarding so the current
NemoClaw installation can own a version-matched gateway.
EOF
    exit 1
  fi
  export NEMOCLAW_GATEWAY_MANAGEMENT="$ROOT/deploy/brev/nemoclaw-managed-gateway.json"
  export NEMOCLAW_OPENSHELL_GATEWAY_CONTAINER_PATCH="${NEMOCLAW_OPENSHELL_GATEWAY_CONTAINER_PATCH:-1}"
  # The launchable's interactive shell exports these paths for its retired
  # externally supervised gateway. They must not override the current managed
  # gateway's user-owned state and generated TLS bundle.
  unset NEMOCLAW_OPENSHELL_GATEWAY_STATE_DIR
  unset OPENSHELL_LOCAL_TLS_DIR
  GATEWAY_WILL_START=1
elif [[ -n "${NEMOCLAW_GATEWAY_MANAGEMENT:-}" \
        && -r "$NEMOCLAW_GATEWAY_MANAGEMENT" ]] \
     && grep -Eq '"mode"[[:space:]]*:[[:space:]]*"nemoclaw-managed"' \
        "$NEMOCLAW_GATEWAY_MANAGEMENT"; then
  GATEWAY_WILL_START=1
fi

for required_command in docker python3; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'Required command is unavailable: %s\n' "$required_command" >&2
    exit 1
  fi
done
for required_path in "$NEMOHERMES_BIN" "$OPENSHELL_BIN"; do
  if [[ -z "$required_path" || ! -x "$required_path" ]]; then
    printf 'Required NemoClaw command is unavailable: %s\n' "$required_path" >&2
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

if ((GATEWAY_WILL_START == 0)) && ! "$OPENSHELL_BIN" sandbox list >/dev/null; then
  cat >&2 <<'EOF'
The selected OpenShell gateway is unavailable. Start or register the gateway
owned by the deployment, verify that `openshell sandbox list` succeeds, and
rerun this script.
EOF
  exit 1
fi

if [[ -z "$NEMOCLAW_SOURCE" ]]; then
  if [[ -d "$HOME/.nemoclaw/source/.git" ]]; then
    NEMOCLAW_SOURCE="$HOME/.nemoclaw/source"
  else
    NEMOHERMES_REAL_BIN="$(readlink -f "$NEMOHERMES_BIN")"
    NEMOCLAW_SOURCE="$(CDPATH= cd -- "$(dirname -- "$NEMOHERMES_REAL_BIN")/.." && pwd)"
  fi
fi

python3 "$ROOT/scripts/prepare-hermes-image.py" --nemoclaw-source "$NEMOCLAW_SOURCE"

HERMES_DOCKERFILE="$NEMOCLAW_SOURCE/agents/hermes/Dockerfile"
if [[ ! -r "$HERMES_DOCKERFILE" ]]; then
  printf 'Prepared Hermes Dockerfile is unavailable: %s\n' "$HERMES_DOCKERFILE" >&2
  exit 1
fi
for argument in "$@"; do
  case "$argument" in
    --from|--from=*)
      printf 'Do not pass --from; this recipe selects its prepared Hermes Dockerfile.\n' >&2
      exit 2
      ;;
  esac
done

printf 'Sandbox name: %s\n' "$SANDBOX_NAME"
printf 'NemoClaw source: %s\n' "$NEMOCLAW_SOURCE"
printf 'NemoHermes command: %s\n' "$NEMOHERMES_BIN"
# This exact repository-owned path is recognized as the trusted Hermes
# Dockerfile. NemoClaw stages the complete repository root and selects the
# generated-image BuildKit path. Omitting --from selects the stock managed
# Hermes image, which cannot contain this recipe's plugin layer.
"$NEMOHERMES_BIN" onboard \
  --name "$SANDBOX_NAME" \
  --from "$HERMES_DOCKERFILE" \
  "$@"
