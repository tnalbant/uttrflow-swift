#!/usr/bin/env python3
"""Prove flake_report finds differing outcomes and refuses an expired quarantine."""

from __future__ import annotations

import datetime as dt
import importlib.util
import json
import sys
import tempfile
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "flake_report", Path(__file__).resolve().parent / "flake_report.py"
)
assert SPEC and SPEC.loader
flake_report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(flake_report)

RUN = """<testsuites><testsuite name="t">
<testcase classname="Audio" name="steady()"/>
<testcase classname="Audio" name="timer()">{timer}</testcase>
<testcase classname="Audio" name="skipped()"><skipped/></testcase>
</testsuite></testsuites>"""


def check(condition: bool, message: str) -> None:
    if not condition:
        print(f"FAIL: {message}", file=sys.stderr)
        raise SystemExit(1)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        green, red = root / "a.xml", root / "b.xml"
        green.write_text(RUN.format(timer=""), encoding="utf-8")
        red.write_text(RUN.format(timer="<failure message='late'/>"), encoding="utf-8")
        runs = [flake_report.outcomes(green), flake_report.outcomes(red), flake_report.outcomes(red)]
        check(flake_report.differing(runs) == {"Audio/timer()": 2}, "differing outcome not found")
        check("Audio/skipped()" not in runs[0], "a skipped test was counted as a pass")
        check(flake_report.differing(runs[1:]) == {}, "a steady failure was called flaky")

        today = dt.date(2026, 1, 10)
        live = {"test": "Audio/timer()", "owner_issue": "1", "expires": "2026-01-10"}
        expired = dict(live, expires="2026-01-09")
        check(flake_report.quarantine_problems([live], today) == [], "a live quarantine was refused")
        check(len(flake_report.quarantine_problems([expired], today)) == 1, "expiry not refused")
        check(len(flake_report.quarantine_problems([{"test": "x"}], today)) == 1, "no owner accepted")

        file = root / "q.json"
        file.write_text(json.dumps([expired]), encoding="utf-8")
        args = ["--check-quarantine", "--quarantine", str(file), "--today", "2026-01-10"]
        check(flake_report.main(args) == 1, "an expired quarantine passed the audit")
    print("flake_report: differing outcomes found, expired quarantine refused")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
