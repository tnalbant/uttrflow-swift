#!/usr/bin/env python3
"""Checks the loose-match audit recognises its reported Swift shapes."""

import os
import tempfile
import unittest

import loose_match_audit


class LooseMatchShapeTests(unittest.TestCase):
    def findings(self, source):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".swift", delete=False) as file:
            file.write(source)
            path = file.name
        self.addCleanup(lambda: os.unlink(path))
        return list(loose_match_audit.findings_in(path))

    def test_resolves_named_small_width_used_by_prefix_equality(self):
        source = "reading.prefix(openingLettersShared) == heard.prefix(openingLettersShared)\n"
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, "Sources"))
            with open(os.path.join(root, "Sources", "Widths.swift"), "w") as file:
                file.write("static let openingLettersShared = 2\n")
            original_roots = loose_match_audit.ROOTS
            loose_match_audit.ROOTS = (os.path.join(root, "Sources"),)
            self.addCleanup(setattr, loose_match_audit, "ROOTS", original_roots)
            findings = self.findings(source)
        self.assertIn("a named short width bounds a text comparison", [item[1] for item in findings])

    def findings_with_widths(self, source, declarations):
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, "Sources"))
            with open(os.path.join(root, "Sources", "Widths.swift"), "w") as file:
                file.write(declarations)
            original_roots, original_path = loose_match_audit.ROOTS, os.environ.get("PATH", "")
            loose_match_audit.ROOTS = (os.path.join(root, "Sources"),)
            os.environ["PATH"] = root
            try:
                return self.findings(source)
            finally:
                loose_match_audit.ROOTS = original_roots
                os.environ["PATH"] = original_path

    def test_planted_named_width_is_flagged_with_no_search_tool_on_path(self):
        source = "return reading.prefix(openingLettersShared) == heard.prefix(openingLettersShared)\n"
        findings = self.findings_with_widths(source, "public static let openingLettersShared = 2\n")
        self.assertIn("a named short width bounds a text comparison", [item[1] for item in findings])

    def test_unresolved_named_width_fails_rather_than_passes(self):
        source = "return reading.prefix(width) == heard.prefix(width)\n"
        with self.assertRaises(loose_match_audit.UnresolvedWidth):
            self.findings_with_widths(source, "let unrelated = 2\n")

    def test_ignores_named_width_beside_an_unrelated_comparison(self):
        source = "let reachable = direction == .forward ? all.prefix(budget) : all.suffix(budget)\n"
        self.assertEqual(self.findings_with_widths(source, "let unrelated = 2\n"), [])

    def test_detects_suffix_table_concatenated_to_a_stem(self):
        findings = self.findings('Set(endings.map { Romaniser.soundKey(stem + $0) })\n')
        self.assertIn("a suffix table decides a text comparison", [item[1] for item in findings])

    def test_detects_adjacent_repeat_collapse_in_filter(self):
        source = "words.enumerated().filter { $0.offset == 0 || words[$0.offset - 1].key != $0.element.key }\n"
        findings = self.findings(source)
        self.assertIn("repeated letters are collapsed before a text comparison", [item[1] for item in findings])

    def test_does_not_flag_general_table_iteration(self):
        findings = self.findings("let first = passage.forms.first ?? \"\"\n")
        self.assertEqual(findings, [])

    def test_ignores_named_width_above_stem_limit(self):
        source = "return found.filter { !$0.hasSuffix(\"/HEAD\") }.prefix(limit)\n"
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, "Sources"))
            with open(os.path.join(root, "Sources", "Widths.swift"), "w") as file:
                file.write("static let limit = 20\n")
            original_roots = loose_match_audit.ROOTS
            loose_match_audit.ROOTS = (os.path.join(root, "Sources"),)
            self.addCleanup(setattr, loose_match_audit, "ROOTS", original_roots)
            findings = self.findings(source)
        self.assertEqual(findings, [])

if __name__ == "__main__":
    unittest.main()
