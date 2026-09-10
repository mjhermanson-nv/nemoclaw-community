#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""Add Ask NemoClaw and local NeMo Relay tracing to a NemoClaw checkout."""

import argparse
from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[1]
PLUGIN_SOURCE = ROOT / "hermes-plugin"
RELAY_SOURCE = ROOT / "relay"
BEGIN_MARKER = "# BEGIN browser-context-knowledge-assistant"
END_MARKER = "# END browser-context-knowledge-assistant"
ANCHOR = "# Verify the immutable security package inventory in the completed image."
MANAGED_POLICY_BEFORE = '      enabled: ["nemoclaw"],'
MANAGED_POLICY_AFTER = (
    '      enabled: ["nemoclaw", "ask-nemoclaw", "observability/nemo_relay"],'
)
PLUGIN_LAYER = f"""{BEGIN_MARKER}
# This source checkout is dedicated to the community example. Keep the complete
# managed Hermes image contract above and add only this recipe's files.
COPY local-plugins/ask-nemoclaw/ /sandbox/.hermes/plugins/ask-nemoclaw/
COPY local-relay/browser-context-knowledge-assistant/plugins.toml \\
     /etc/nemo-relay/config/plugins.toml
RUN /opt/hermes/.venv/bin/python -c \\
       'from importlib.metadata import version; print("Using Hermes-bundled nemo-relay", version("nemo-relay"))' \\
    && uv pip check --python /opt/hermes/.venv/bin/python \\
    && mkdir -p /sandbox/.hermes-data/nemo-relay/atif \\
    && chown -R sandbox:sandbox \\
       /sandbox/.hermes/plugins/ask-nemoclaw \\
       /sandbox/.hermes-data/nemo-relay \\
    && chmod -R a+rX /sandbox/.hermes/plugins/ask-nemoclaw \\
    && chown -R root:root /etc/nemo-relay \\
    && chmod 555 /etc/nemo-relay /etc/nemo-relay/config \\
    && chmod 444 /etc/nemo-relay/config/plugins.toml
ENV HERMES_NEMO_RELAY_PLUGINS_TOML=/etc/nemo-relay/config/plugins.toml
{END_MARKER}

"""


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Prepare the managed NemoClaw Hermes image for this recipe"
    )
    parser.add_argument("--nemoclaw-source", required=True, type=Path)
    args = parser.parse_args()

    source = args.nemoclaw_source.resolve()
    dockerfile = source / "agents" / "hermes" / "Dockerfile"
    config_dir = source / "agents" / "hermes" / "config"
    plugin_config_candidates = (
        config_dir / "hermes-config.ts",
        config_dir / "managed-policy.ts",
    )
    plugin_config = next(
        (candidate for candidate in plugin_config_candidates if candidate.is_file()),
        None,
    )
    if (
        not (source / ".git").exists()
        or not dockerfile.is_file()
        or plugin_config is None
    ):
        raise SystemExit("--nemoclaw-source must be a NemoClaw source checkout")

    text = dockerfile.read_text(encoding="utf-8")
    if (BEGIN_MARKER in text) != (END_MARKER in text):
        raise SystemExit(
            "The managed example layer is incomplete; restore a clean Hermes "
            "Dockerfile before continuing"
        )
    if BEGIN_MARKER in text:
        start = text.index(BEGIN_MARKER)
        finish = text.index(END_MARKER, start) + len(END_MARKER)
        updated = text[:start] + PLUGIN_LAYER.strip() + text[finish:]
        if updated != text:
            dockerfile.write_text(updated, encoding="utf-8")
            print(f"Updated browser context assistant image layer: {dockerfile}")
        else:
            print(f"Browser context assistant image layer is current: {dockerfile}")
        return
    if ANCHOR not in text:
        raise SystemExit(
            "The managed Hermes Dockerfile layout has changed; review the current "
            "NemoClaw plugin installation guide before applying this example"
        )

    policy_text = plugin_config.read_text(encoding="utf-8")
    if (
        MANAGED_POLICY_AFTER not in policy_text
        and MANAGED_POLICY_BEFORE not in policy_text
    ):
        raise SystemExit(
            "The managed Hermes plugin policy has changed; review the current "
            "NemoClaw plugin configuration before applying this example"
        )

    destinations = (
        (PLUGIN_SOURCE, source / "local-plugins" / "ask-nemoclaw"),
        (
            RELAY_SOURCE,
            source / "local-relay" / "browser-context-knowledge-assistant",
        ),
    )
    for _, destination in destinations:
        if destination.exists():
            raise SystemExit(
                f"Refusing to replace existing path: {destination}. "
                "Use a dedicated clean checkout."
            )

    for origin, destination in destinations:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(origin, destination)
    dockerfile.write_text(
        text.replace(ANCHOR, PLUGIN_LAYER + ANCHOR, 1), encoding="utf-8"
    )
    if MANAGED_POLICY_BEFORE in policy_text:
        plugin_config.write_text(
            policy_text.replace(MANAGED_POLICY_BEFORE, MANAGED_POLICY_AFTER, 1),
            encoding="utf-8",
        )

    print(f"Copied plugin to: {destinations[0][1]}")
    print(f"Copied Relay configuration to: {destinations[1][1]}")
    print(f"Updated managed Dockerfile: {dockerfile}")
    print(f"Updated managed plugin configuration: {plugin_config}")


if __name__ == "__main__":
    main()
