# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

import importlib.util
from pathlib import Path
import stat
import sys
import types
import tempfile
import unittest


HELPER = Path(__file__).parents[1] / "hermes-plugin" / "configure_dashboard_auth.py"


def load_helper():
    plugins = types.ModuleType("plugins")
    dashboard_auth = types.ModuleType("plugins.dashboard_auth")
    basic = types.ModuleType("plugins.dashboard_auth.basic")
    basic.hash_password = lambda password: f"hash:{len(password)}"
    sys.modules["plugins"] = plugins
    sys.modules["plugins.dashboard_auth"] = dashboard_auth
    sys.modules["plugins.dashboard_auth.basic"] = basic
    spec = importlib.util.spec_from_file_location("configure_dashboard_auth", HELPER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class DashboardAuthHelperTests(unittest.TestCase):
    def test_replace_removes_plaintext_and_preserves_other_values(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            env_path = Path(directory) / ".env"
            env_path.write_text(
                "OTHER_SETTING=preserved\n"
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=old-plaintext\n",
                encoding="utf-8",
            )

            helper.replace_managed_entries(
                env_path,
                {
                    "HERMES_DASHBOARD_BASIC_AUTH_USERNAME": "admin",
                    "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH": "scrypt-hash",
                    "HERMES_DASHBOARD_BASIC_AUTH_SECRET": "signing-secret",
                },
            )

            content = env_path.read_text(encoding="utf-8")
            self.assertIn("OTHER_SETTING=preserved", content)
            self.assertNotIn("old-plaintext", content)
            self.assertNotIn("HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=", content)
            self.assertIn(
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=scrypt-hash", content
            )
            self.assertEqual(stat.S_IMODE(env_path.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
