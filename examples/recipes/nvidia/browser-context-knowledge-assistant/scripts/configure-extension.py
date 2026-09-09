#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

import argparse
import json
from pathlib import Path
import shutil
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "extension"


def validated_origin(value: str) -> str:
    parsed = urlsplit(value.rstrip("/"))
    if not parsed.hostname:
        raise argparse.ArgumentTypeError("Hermes origin must include a host")
    loopback_hosts = {"127.0.0.1", "localhost", "::1"}
    if parsed.scheme != "https" and not (
        parsed.scheme == "http" and parsed.hostname in loopback_hosts
    ):
        raise argparse.ArgumentTypeError(
            "Hermes origin must use HTTPS, except for an HTTP loopback origin"
        )
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise argparse.ArgumentTypeError("Hermes origin cannot contain credentials, a query, or a fragment")
    if parsed.path not in {"", "/"}:
        raise argparse.ArgumentTypeError("Hermes origin cannot contain a path")
    return value.rstrip("/")


parser = argparse.ArgumentParser(description="Build an unpacked Ask NemoClaw extension")
parser.add_argument("--hermes-origin", required=True, type=validated_origin)
parser.add_argument("--output", type=Path, default=ROOT / "build" / "extension")
args = parser.parse_args()

args.output.mkdir(parents=True, exist_ok=True)
for name in ("service-worker.js", "sidepanel.html", "sidepanel.css", "sidepanel.js"):
    shutil.copy2(SOURCE / name, args.output / name)

manifest_text = (SOURCE / "manifest.template.json").read_text(encoding="utf-8")
manifest_text = manifest_text.replace("__HERMES_ORIGIN__", args.hermes_origin)
manifest = json.loads(manifest_text)
(args.output / "manifest.json").write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)

config_text = (SOURCE / "config.template.js").read_text(encoding="utf-8")
config_text = config_text.replace("__HERMES_ORIGIN_JSON__", json.dumps(args.hermes_origin))
(args.output / "config.js").write_text(config_text, encoding="utf-8")

print(f"Built unpacked extension: {args.output}")
