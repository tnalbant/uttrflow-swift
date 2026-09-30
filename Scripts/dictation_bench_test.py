#!/usr/bin/env python3
"""Proves `jobs` and `score` fail loudly on an empty selection or an empty run, instead of exiting 0."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.join(HERE, "dictation_bench.py")
sys.path.insert(0, HERE)
import dictation_bench as bench  # noqa: E402

CLIP = {
    "id": "known",
    "wav": "known.wav",
    "vocabulary": [],
    "category": "reply",
    "variant": "clean",
    "language": "english",
    "voice": "Samantha",
    "spoken": "hello world",
    "written": "Hello world.",
    "devanagari": None,
}


def result_event(clip_id, text="Hello world."):
    return {
        "event": "result",
        "id": clip_id,
        "text": text,
        "events": [
            {"kind": "asr", "text": "hello world", "t0": 0, "t1": 1},
            {"kind": "clean", "t0": 1, "t1": 1.2},
            {"kind": "keyup", "t": 1.5},
        ],
        "wait": 0.1,
        "audio": 1.0,
        "cpu": 0.1,
        "peakMB": 50,
        "cleaner": "shipping",
        "mode": "fast",
    }


class BenchTests(unittest.TestCase):
    def setUp(self):
        self.out = tempfile.mkdtemp(prefix="uttrflow-bench-")
        self.addCleanup(shutil.rmtree, self.out, ignore_errors=True)
        with open(os.path.join(self.out, "corpus.json"), "w") as handle:
            json.dump([CLIP], handle)

    def run_bench(self, *args):
        return subprocess.run(
            [sys.executable, BENCH, "--out", self.out, *args],
            capture_output=True, text=True,
        )

    def write_run(self, *lines):
        path = os.path.join(self.out, "run.jsonl")
        with open(path, "w") as handle:
            for line in lines:
                handle.write(line + "\n")
        return path

    def test_devanagari_marks_remain_inside_words_when_punctuation_is_removed(self):
        self.assertEqual(
            bench.normalise("मैं नहीं आऊँगा, पचास लाख।"),
            ["मैं", "नहीं", "आऊँगा", "पचास", "लाख"],
        )

    def test_devanagari_matra_errors_are_counted_as_word_edits(self):
        self.assertEqual(
            bench.errors(
                ["कल शाम को मैं घर जल्दी पहुँच गया"],
                "कल शाम को मै घर जल्दी पहुंच गया",
            ),
            (2, 8),
        )

    def test_an_extra_devanagari_word_is_counted(self):
        self.assertEqual(
            bench.errors(["मैं नहीं आऊँगा"], "मैं नहीं आऊँगा बिल्कुल"),
            (1, 3),
        )

    def test_english_normalisation_and_scoring_are_unchanged(self):
        self.assertEqual(
            bench.normalise("Hello, WORLD! I paid 3 dollars."),
            ["hello", "world", "i", "paid", "three", "dollars"],
        )
        self.assertEqual(
            bench.errors(["Hello, world! I paid three dollars."], "Hello world, I paid four dollars."),
            (1, 6),
        )

    # jobs

    def test_a_matching_category_produces_jobs(self):
        run = self.run_bench("jobs", "--categories", "reply")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("known", run.stdout)

    def test_a_category_typo_that_selects_nothing_fails_instead_of_printing_a_blank_line(self):
        run = self.run_bench("jobs", "--categories", "typo")
        self.assertNotEqual(run.returncode, 0)
        self.assertNotIn("known", run.stdout)

    # score

    def test_a_valid_run_is_scored_and_exits_zero(self):
        run_path = self.write_run("BENCH " + json.dumps(result_event("known")))
        run = self.run_bench("score", run_path)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("failed: none", run.stdout)

    def test_an_empty_run_file_fails_instead_of_printing_failed_none(self):
        run_path = self.write_run()
        run = self.run_bench("score", run_path)
        self.assertNotEqual(run.returncode, 0)
        self.assertNotIn("failed: none", run.stdout)

    def test_an_unknown_result_id_is_reported_and_fails_when_nothing_else_scores(self):
        run_path = self.write_run("BENCH " + json.dumps(result_event("unknown-clip")))
        run = self.run_bench("score", run_path)
        self.assertNotEqual(run.returncode, 0)
        combined = run.stdout + run.stderr
        self.assertIn("unknown-clip", combined)


if __name__ == "__main__":
    unittest.main(verbosity=1)
