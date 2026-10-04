#!/usr/bin/env python3
"""Proves transcribe refuses negative report limits before starting a measurement."""

import os
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BINARY = os.path.join(ROOT, ".build", "debug", "uttrflow-eval")


class TranscribeLimitArgumentTests(unittest.TestCase):
    """Drives the built executable and checks validation before corpus setup."""

    def run_with(self, *arguments):
        return subprocess.run(
            [BINARY, "transcribe", *arguments], capture_output=True, text=True, timeout=120
        )

    def assert_refused(self, option, expected):
        # Joined with "=", since a separate "-1" reads as an option rather than a value.
        finished = self.run_with(f"{option}=-1")
        self.assertEqual(finished.returncode, 64, finished.stderr)
        said = finished.stdout + finished.stderr
        self.assertIn(expected, said)
        self.assertIn("usage:", said.lower())
        self.assertNotIn("Nothing to measure", said)

    def test_negative_findings_is_refused(self):
        self.assert_refused("--findings", "--findings must be zero or greater")

    def test_negative_passage_limit_is_refused(self):
        self.assert_refused("--passage-limit", "--passage-limit must be zero or greater")

    def test_zero_limits_are_accepted(self):
        with tempfile.TemporaryDirectory(prefix="uttrflow-eval-results-") as results:
            finished = self.run_with(
                "--findings", "0", "--passage-limit", "0", "--summarise", "--results-path", results
            )
        self.assertEqual(finished.returncode, 0, finished.stderr)
        self.assertIn("Nothing measured yet.", finished.stdout)
        self.assertNotIn("usage:", (finished.stdout + finished.stderr).lower())


if __name__ == "__main__":
    unittest.main(verbosity=1)
