#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

node --check "$ROOT/extension/service-worker.js"
node --check "$ROOT/extension/sidepanel.js"
bash -n "$ROOT/scripts/check-connection.sh"
bash -n "$ROOT/scripts/onboard.sh"
bash -n "$ROOT/scripts/configure-brev-nginx.sh"
grep -Fq 'io.containerd.snapshotter.v1' "$ROOT/scripts/onboard.sh"
grep -Fq 'openshell sandbox list' "$ROOT/scripts/onboard.sh"
if grep -Eq '^[[:space:]]*--from' "$ROOT/scripts/onboard.sh"; then
  printf 'onboarding unexpectedly routes the generated Hermes image through the legacy gateway builder\n' >&2
  exit 1
fi
if "$ROOT/scripts/check-connection.sh" 'https://hermes.example.com/path' >/dev/null 2>&1; then
  printf 'connection checker accepted a URL path instead of an exact origin\n' >&2
  exit 1
fi
node "$ROOT/tests/test_sidepanel_parsing.js"
"$PYTHON_BIN" "$ROOT/tests/test_plugin_api.py" -v
"$PYTHON_BIN" "$ROOT/scripts/configure-extension.py" \
  --hermes-origin https://hermes.example.com \
  --output "$ROOT/build/verification-extension"
"$PYTHON_BIN" "$ROOT/scripts/configure-extension.py" \
  --hermes-origin http://127.0.0.1:18789 \
  --output "$ROOT/build/loopback-verification-extension"
"$PYTHON_BIN" "$ROOT/scripts/configure-extension.py" \
  --hermes-origin https://nemoclaw.example.com \
  --service-path /ask-nemoclaw \
  --dashboard-path / \
  --output "$ROOT/build/brev-verification-extension"
test -s "$ROOT/build/verification-extension/manifest.json"
test -s "$ROOT/build/verification-extension/config.js"
test -s "$ROOT/build/loopback-verification-extension/manifest.json"
grep -Fq 'servicePath: "/ask-nemoclaw"' "$ROOT/build/brev-verification-extension/config.js"
grep -Fq 'dashboardPath: "/"' "$ROOT/build/brev-verification-extension/config.js"
grep -Fq 'listen 0.0.0.0:__PROXY_PORT__' "$ROOT/deploy/nginx/ask-nemoclaw-server.conf"
grep -Fq 'proxy_set_header Host 127.0.0.1:__DASHBOARD_PORT__' "$ROOT/deploy/nginx/ask-nemoclaw-server.conf"
grep -Fq 'NEMOCLAW_DASHBOARD_PORT' "$ROOT/scripts/configure-brev-nginx.sh"
grep -Fq 'NEMOCLAW_BREV_PROXY_PORT' "$ROOT/scripts/configure-brev-nginx.sh"
grep -Fq 'sudo nginx -t' "$ROOT/scripts/configure-brev-nginx.sh"
test -s "$ROOT/assets/ask-nemoclaw-browser-context.png"
test -s "$ROOT/assets/ask-nemoclaw-architecture.png"
test -s "$ROOT/assets/ask-nemoclaw-architecture.svg"
grep -Fq 'sidepanel_browser_fixture.html' "$ROOT/tests/demo_screenshot_fixture.html"
if grep -Eiq 'confidential compute|SEV-SNP|KubeVirt|Google Docs.*branding' \
  "$ROOT/assets/ask-nemoclaw-architecture.svg"; then
  printf 'community architecture unexpectedly contains deployment-specific routing\n' >&2
  exit 1
fi

IMAGE_FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$IMAGE_FIXTURE"' EXIT
mkdir -p "$IMAGE_FIXTURE/.git" "$IMAGE_FIXTURE/agents/hermes/config"
printf '%s\n' '# managed Hermes image' '# Verify the immutable security package inventory in the completed image.' \
  > "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
printf '%s\n' \
  'const DASHBOARD_ROUTING_KEYS = [' \
  '  "_nemoclaw_upstream",' \
  '] as const;' \
  '' \
  'const MANAGED_POLICY_PATHS = [' \
  '  "updates.refresh_cua_driver",' \
  '  "plugins.enabled",' \
  '] as const;' \
  '' \
  'export const config = {' \
  '    plugins: {' \
  '      enabled: ["nemoclaw"],' \
  '    },' \
  '};' \
  > "$IMAGE_FIXTURE/agents/hermes/config/hermes-config.ts"
"$PYTHON_BIN" "$ROOT/scripts/prepare-hermes-image.py" --nemoclaw-source "$IMAGE_FIXTURE"
"$PYTHON_BIN" "$ROOT/scripts/prepare-hermes-image.py" --nemoclaw-source "$IMAGE_FIXTURE"
test -s "$IMAGE_FIXTURE/local-plugins/ask-nemoclaw/dashboard/plugin_api.py"
test -s "$IMAGE_FIXTURE/local-relay/browser-context-knowledge-assistant/plugins.toml"
grep -Fq '# BEGIN browser-context-knowledge-assistant' "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
test "$(grep -Fc '# BEGIN browser-context-knowledge-assistant' "$IMAGE_FIXTURE/agents/hermes/Dockerfile")" -eq 1
grep -Fq 'COPY local-plugins/ask-nemoclaw/ /opt/hermes/plugins/ask-nemoclaw/' \
  "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
grep -Fq 'ADD --checksum=sha256:0ce7103aec546766649c182619d16aa6ad07439e4d0ebd16d95c5004afb3e56a' \
  "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
grep -Fq 'nemo_relay-0.7.2-cp311-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl' \
  "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
grep -Fq 'assert version("nemo-relay") == "0.7.2"' \
  "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
grep -Fq 'uv pip check --python /opt/hermes/.venv/bin/python' \
  "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
grep -Fq 'HERMES_NEMO_RELAY_PLUGINS_TOML=/etc/nemo-relay/config/plugins.toml' \
  "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
grep -Fq 'HERMES_ASK_NEMOCLAW_LOOPBACK_MODE=1' \
  "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
grep -Fq '/etc/nemoclaw/ask-nemoclaw-loopback-mode' \
  "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
grep -Fq 'enabled: ["nemoclaw", "ask-nemoclaw", "observability/nemo_relay"]' \
  "$IMAGE_FIXTURE/agents/hermes/config/hermes-config.ts"
grep -Fq '"plugins",' \
  "$IMAGE_FIXTURE/agents/hermes/config/hermes-config.ts"
if grep -Fq '"plugins.enabled",' \
  "$IMAGE_FIXTURE/agents/hermes/config/hermes-config.ts"; then
  printf 'plugin enablement must not extend Hermes profile managed paths\n' >&2
  exit 1
fi
grep -Fq 'output_directory = "/sandbox/.hermes-data/nemo-relay/atif"' \
  "$IMAGE_FIXTURE/local-relay/browser-context-knowledge-assistant/plugins.toml"
if grep -Eq 'opentelemetry|https?://' \
  "$IMAGE_FIXTURE/local-relay/browser-context-knowledge-assistant/plugins.toml"; then
  printf 'base Relay configuration unexpectedly contains an external collector\n' >&2
  exit 1
fi

printf '%s\n' "Verification completed."
