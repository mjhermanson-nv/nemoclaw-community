#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

node --check "$ROOT/extension/service-worker.js"
node --check "$ROOT/extension/sidepanel.js"
bash -n "$ROOT/scripts/check-connection.sh"
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
test -s "$ROOT/build/verification-extension/manifest.json"
test -s "$ROOT/build/verification-extension/config.js"
test -s "$ROOT/build/loopback-verification-extension/manifest.json"
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
grep -Fq 'COPY local-plugins/ask-nemoclaw/' "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
grep -Fq 'Using Hermes-bundled nemo-relay' "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
if grep -Eq 'files\.pythonhosted|uv pip install.*nemo.?relay' \
  "$IMAGE_FIXTURE/agents/hermes/Dockerfile"; then
  printf 'prepared image unexpectedly replaces the Hermes-bundled Relay package\n' >&2
  exit 1
fi
grep -Fq 'HERMES_NEMO_RELAY_PLUGINS_TOML=/etc/nemo-relay/config/plugins.toml' \
  "$IMAGE_FIXTURE/agents/hermes/Dockerfile"
grep -Fq 'enabled: ["nemoclaw", "ask-nemoclaw", "observability/nemo_relay"]' \
  "$IMAGE_FIXTURE/agents/hermes/config/hermes-config.ts"
grep -Fq 'output_directory = "/sandbox/.hermes-data/nemo-relay/atif"' \
  "$IMAGE_FIXTURE/local-relay/browser-context-knowledge-assistant/plugins.toml"
if grep -Eq 'opentelemetry|https?://' \
  "$IMAGE_FIXTURE/local-relay/browser-context-knowledge-assistant/plugins.toml"; then
  printf 'base Relay configuration unexpectedly contains an external collector\n' >&2
  exit 1
fi

printf '%s\n' "Verification completed."
