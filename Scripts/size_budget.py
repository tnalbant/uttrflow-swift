#!/usr/bin/env python3
"""Fails when the app bundle or the resolved Swift packages outgrow `Scripts/size_budget.json` (see `Docs/performance.md`)."""

import argparse
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUDGET = os.path.join(ROOT, "Scripts", "size_budget.json")
RESOLVED = os.path.join(ROOT, "Package.resolved")


def load_budget(path=BUDGET):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def tree_bytes(path):
    """Sum of regular file sizes under path, symlinks not followed, so the figure is the same on every file system."""
    total = 0
    for directory, _, files in os.walk(path):
        for name in files:
            full = os.path.join(directory, name)
            if not os.path.islink(full):
                total += os.path.getsize(full)
    return total


def zip_bytes(app):
    with tempfile.TemporaryDirectory() as scratch:
        archive = os.path.join(scratch, "app.zip")
        subprocess.run(["ditto", "-c", "-k", "--keepParent", app, archive], check=True)
        return os.path.getsize(archive)


def resolved_packages(path=RESOLVED):
    with open(path, encoding="utf-8") as handle:
        return len(json.load(handle).get("pins", []))


def over_budget(measured, budget):
    """The measures over their limit, as (name, measured, limit); a measure missing from the budget is over it."""
    return [(name, value, budget.get(name)) for name, value in measured.items()
            if budget.get(name) is None or value > budget[name]]


def report(measured, budget):
    for name, value in measured.items():
        limit = budget.get(name)
        print(f"  {name:<18} {value:>13,}  budget {'none' if limit is None else format(limit, ','):>13}")
    failures = over_budget(measured, budget)
    for name, value, limit in failures:
        print(f"error: {name} is {value:,}, over its budget of {limit}. Shrink it, or raise "
              f"Scripts/size_budget.json in a reviewed change that says why.", file=sys.stderr)
    return 1 if failures else 0


def self_test():
    budget = {"app_bytes": 100, "resolved_packages": 2}
    assert over_budget({"app_bytes": 100, "resolved_packages": 2}, budget) == []
    assert over_budget({"app_bytes": 101}, budget) == [("app_bytes", 101, 100)]
    assert over_budget({"resolved_packages": 3}, budget) == [("resolved_packages", 3, 2)]
    assert over_budget({"app_zip_bytes": 1}, budget) == [("app_zip_bytes", 1, None)]
    with tempfile.TemporaryDirectory() as scratch:
        os.makedirs(os.path.join(scratch, "A.app", "Contents", "Resources"))
        with open(os.path.join(scratch, "A.app", "Contents", "Resources", "blob"), "wb") as handle:
            handle.write(b"\0" * 150)
        os.symlink("blob", os.path.join(scratch, "A.app", "Contents", "Resources", "link"))
        assert tree_bytes(os.path.join(scratch, "A.app")) == 150
        assert over_budget({"app_bytes": tree_bytes(os.path.join(scratch, "A.app"))}, budget)
        resolved = os.path.join(scratch, "Package.resolved")
        with open(resolved, "w", encoding="utf-8") as handle:
            json.dump({"pins": [{"identity": "a"}, {"identity": "b"}, {"identity": "c"}]}, handle)
        assert resolved_packages(resolved) == 3
    assert set(load_budget()) == {"app_bytes", "app_zip_bytes", "resolved_packages"}
    print("size budget self-test passed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", help="a built .app bundle to measure as well as the resolved packages")
    parser.add_argument("--self-test", action="store_true", help="prove the check bites, then check the packages")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    budget = load_budget()
    measured = {"resolved_packages": resolved_packages()}
    if args.app:
        measured["app_bytes"] = tree_bytes(args.app)
        measured["app_zip_bytes"] = zip_bytes(args.app)
    else:
        budget = {"resolved_packages": budget["resolved_packages"]}
    return report(measured, budget)


if __name__ == "__main__":
    sys.exit(main())
