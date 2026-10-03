#!/usr/bin/env python3
"""Refuses a test file named after an issue number instead of the behaviour it pins.

A regression case belongs beside the other cases for the same behaviour, with the issue
number carried as a `.bug(id:)` trait, so the suite still explains itself once the issue
is closed. See CONTRIBUTING.md.
"""

import re
import subprocess
import sys

PATTERN = re.compile(r"(^|/)Issue[0-9]+[^/]*$")


def offending(paths):
    return [path for path in paths if path.startswith("Tests/") and PATTERN.search(path)]


def tracked_and_untracked():
    out = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "Tests"],
        check=True, capture_output=True, text=True,
    ).stdout
    return out.splitlines()


def main():
    bad = offending(tracked_and_untracked())
    for path in bad:
        print(f"{path}: name the file for the behaviour it tests and put the issue in a .bug(id:) trait")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
