#!/usr/bin/env python3
"""Proves the Python imports audit refuses an unpinned third-party import and accepts a pinned one."""

import os
import tempfile
import unittest

import python_imports_audit

SHA = "a" * 64


class PythonImportsAuditTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.allow = os.path.join(self.root, "allow.txt")
        self.lock = os.path.join(self.root, "requirements.lock")

    def write(self, name, text):
        with open(os.path.join(self.root, name), "w", encoding="utf-8") as file:
            file.write(text)

    def problems(self):
        return python_imports_audit.audit(self.root, self.allow, self.lock)

    def test_todays_scripts_pass(self):
        self.assertEqual(python_imports_audit.audit(), [])

    def test_standard_library_and_sibling_pass(self):
        self.write("helper.py", "X = 1\n")
        self.write("tool.py", "import json\nfrom xml.sax import saxutils\nimport helper\n")
        self.assertEqual(self.problems(), [])

    def test_unpinned_import_fails_with_file_and_line(self):
        self.write("fit.py", "import os\nimport numpy as np\n")
        problems = self.problems()
        self.assertEqual(len(problems), 1)
        self.assertIn("fit.py:2:", problems[0])
        self.assertIn("'numpy'", problems[0])

    def test_allowed_import_without_lock_fails(self):
        self.write("fit.py", "import numpy\n")
        self.write("allow.txt", f"numpy numpy==2.1.0 sha256:{SHA} BSD-3-Clause\n")
        self.assertIn("missing", self.problems()[0])

    def test_allowed_import_with_hashed_lock_passes(self):
        self.write("fit.py", "import numpy\n")
        self.write("allow.txt", f"numpy numpy==2.1.0 sha256:{SHA} BSD-3-Clause\n")
        self.write("requirements.lock", f"numpy==2.1.0 \\\n    --hash=sha256:{SHA}\n")
        self.assertEqual(self.problems(), [])

    def test_malformed_allow_line_fails(self):
        self.write("allow.txt", "numpy numpy>=2\n")
        self.assertEqual(len(self.problems()), 1)


if __name__ == "__main__":
    unittest.main()
