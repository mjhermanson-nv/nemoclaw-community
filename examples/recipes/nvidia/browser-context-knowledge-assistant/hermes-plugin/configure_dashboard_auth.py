#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""Configure Hermes dashboard basic authentication without storing plaintext."""

from __future__ import annotations

import getpass
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

from plugins.dashboard_auth.basic import hash_password


MANAGED_KEYS = {
    "HERMES_DASHBOARD_BASIC_AUTH_USERNAME",
    "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD",
    "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH",
    "HERMES_DASHBOARD_BASIC_AUTH_SECRET",
}


def hermes_env_path() -> Path:
    result = subprocess.run(
        ["hermes", "config", "env-path"],
        check=True,
        capture_output=True,
        text=True,
    )
    path = result.stdout.strip()
    if not path:
        raise SystemExit("Hermes did not return its environment-file path")
    return Path(path)


def prompt_username() -> str:
    username = input("Dashboard username [admin]: ").strip() or "admin"
    if not username or len(username) > 128 or "=" in username or "\n" in username:
        raise SystemExit("Username must be 1-128 characters and cannot contain '='")
    return username


def prompt_password() -> str:
    password = getpass.getpass("Dashboard password: ")
    confirmation = getpass.getpass("Confirm dashboard password: ")
    if password != confirmation:
        raise SystemExit("Passwords do not match")
    if len(password) < 12:
        raise SystemExit("Use a password or passphrase with at least 12 characters")
    return password


def replace_managed_entries(path: Path, values: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    retained = [
        line
        for line in existing
        if line.split("=", 1)[0].strip() not in MANAGED_KEYS
    ]
    updated = retained + [f"{key}={value}" for key, value in values.items()]

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent, text=True
    )
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write("\n".join(updated) + "\n")
        os.replace(temporary_name, path)
        os.chmod(path, 0o600)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def main() -> None:
    username = prompt_username()
    password = prompt_password()
    password_hash = hash_password(password)
    password = ""

    path = hermes_env_path()
    replace_managed_entries(
        path,
        {
            "HERMES_DASHBOARD_BASIC_AUTH_USERNAME": username,
            "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH": password_hash,
            "HERMES_DASHBOARD_BASIC_AUTH_SECRET": secrets.token_urlsafe(48),
        },
    )
    print(f"Dashboard authentication configured in {path}.")
    print("Only a scrypt password hash and a random session-signing secret were stored.")
    print("Exit the sandbox shell, then restart the Hermes gateway from the Brev host.")


if __name__ == "__main__":
    main()
