#!/usr/bin/env python3
"""Proves the data manifest check fails on a missing entry or an edited byte."""

import json
import os
import subprocess
import sys
import tempfile
import unittest

import data_manifest


class DataManifestTests(unittest.TestCase):
    def tree(self, origin="authored"):
        root = tempfile.mkdtemp()
        folder = os.path.join(root, "Sources", "Module", "Resources")
        os.makedirs(folder)
        os.makedirs(os.path.join(root, "Resources"))
        asset = os.path.join(folder, "table.json")
        with open(asset, "wb") as handle:
            handle.write(b"{}")
        entry = {
            "path": os.path.join("Sources", "Module", "Resources", "table.json"),
            "origin": origin,
            "licence": "MIT",
            "redistribution": True,
            "sha256": data_manifest.digest(asset),
            "bytes": 2,
        }
        self.write(root, [entry])
        return root, asset, entry

    def write(self, root, entries):
        with open(os.path.join(root, data_manifest.MANIFEST), "w", encoding="utf-8") as handle:
            json.dump({"assets": entries}, handle)

    def test_matching_tree_passes(self):
        root, _, _ = self.tree()
        self.assertEqual(data_manifest.check(root), ([], []))

    def test_removed_entry_fails(self):
        root, _, _ = self.tree()
        self.write(root, [])
        self.assertIn("bundled but not in", data_manifest.check(root)[0][0])

    def test_edited_byte_fails(self):
        root, asset, _ = self.tree()
        with open(asset, "wb") as handle:
            handle.write(b"[]")
        self.assertIn("SHA-256 differs", data_manifest.check(root)[0][0])

    def test_update_refreshes_only_digest_and_size_for_existing_entries(self):
        root, asset, original_entry = self.tree(origin="generated")
        original_entry["note"] = "keep this metadata"
        self.write(root, [original_entry])
        with open(asset, "wb") as handle:
            handle.write(b"[1, 2, 3]")

        changed, errors = data_manifest.update(root)

        self.assertEqual((changed, errors), (1, []))
        with open(os.path.join(root, data_manifest.MANIFEST), encoding="utf-8") as handle:
            updated = json.load(handle)["assets"][0]
        self.assertEqual(updated["origin"], "generated")
        self.assertEqual(updated["note"], "keep this metadata")
        self.assertEqual(updated["sha256"], data_manifest.digest(asset))
        self.assertEqual(updated["bytes"], os.path.getsize(asset))
        self.assertEqual(data_manifest.check(root), ([], []))

    def test_update_does_not_add_an_entry_for_an_unlisted_file(self):
        root, _, _ = self.tree()
        self.write(root, [])

        changed, errors = data_manifest.update(root)

        self.assertEqual((changed, errors), (0, []))
        self.assertIn("bundled but not in", data_manifest.check(root)[0][0])

    def test_update_command_refreshes_a_stale_entry(self):
        root, asset, _ = self.tree()
        with open(asset, "wb") as handle:
            handle.write(b"updated")

        result = subprocess.run(
            [
                sys.executable,
                os.path.join(os.path.dirname(data_manifest.__file__), "data_manifest.py"),
                "--root",
                root,
                "--update",
            ],
            capture_output=True,
            check=False,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("updated 1 existing entries", result.stdout)
        self.assertEqual(data_manifest.check(root), ([], []))

    def test_stale_entry_fails(self):
        root, asset, _ = self.tree()
        os.remove(asset)
        self.assertIn("not bundled", data_manifest.check(root)[0][0])

    def test_third_party_needs_source_and_revision(self):
        root, _, entry = self.tree(origin="third-party")
        self.assertIn("missing source, revision", data_manifest.check(root)[0][0])
        entry.update(source="https://example.com/list", revision="1.0")
        self.write(root, [entry])
        self.assertEqual(data_manifest.check(root)[0], [])

    def test_unrecorded_origin_is_reported_not_failed(self):
        root, _, _ = self.tree(origin="unrecorded")
        failures, notes = data_manifest.check(root)
        self.assertEqual(failures, [])
        self.assertIn("owner to confirm", notes[0])

    def test_unknown_origin_fails(self):
        root, _, _ = self.tree(origin="found")
        self.assertIn("origin must be one of", data_manifest.check(root)[0][0])


if __name__ == "__main__":
    unittest.main()
