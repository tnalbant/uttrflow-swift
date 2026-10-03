#!/usr/bin/env python3
"""Refuses a file or directory at the repository root that is not on the allowlist.

A script run from the wrong directory writes where it was started, and nothing else looked at
the root, so 26 generated artboards sat there for days. Add a new root entry to ROOT_ENTRIES
on purpose, in the same change that creates it.

Usage:  python3 Scripts/root_layout_audit.py             (belongs in `make verify`)
        python3 Scripts/root_layout_audit.py --self-test   also proves a stray file is caught
"""
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parent.parent

ROOT_ENTRIES = {
    ".claude", ".coderabbit.yaml", ".cursor", ".githooks", ".github", ".gitignore",
    ".gitleaks.toml", ".swift-format", "AGENTS.md", "CHANGELOG.md", "CLAUDE.md",
    "CODE_OF_CONDUCT.md", "CONTRIBUTING.md", "Design", "Docs", "LICENSE", "Makefile",
    "Package.resolved", "Package.swift", "README.md", "RELEASING.md",
    "Resources", "SECURITY.md", "Scripts", "Sources", "TRADEMARK.md", "Tests", "UITests",
    "_typos.toml", "graphflow.yaml", "lychee.toml", "osv-scanner.toml",
}


def stray_root_entries(root):
    """Returns the root entries, tracked or untracked-but-not-ignored, that are not allowed."""
    listed = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root, capture_output=True, text=True, check=True,
    ).stdout.split("\0")
    return sorted({path.split("/")[0] for path in listed if path} - ROOT_ENTRIES)


def self_test():
    """Proves the audit passes an allowed root and fails a stray file."""
    print("root_layout_audit self-test")
    with tempfile.TemporaryDirectory() as scratch:
        subprocess.run(["git", "init", "-q", scratch], check=True)
        (Path(scratch) / "README.md").write_text("ok")
        assert stray_root_entries(scratch) == [], "an allowed root must pass"
        (Path(scratch) / "Main-Home.dc.html").write_text("stray")
        found = stray_root_entries(scratch)
        assert found == ["Main-Home.dc.html"], f"a stray root file must be caught, got {found}"
    print("ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    strays = stray_root_entries(PACKAGE_ROOT)
    if strays:
        print("root_layout_audit: not allowed at the repository root:", file=sys.stderr)
        for name in strays:
            print(f"  {name}", file=sys.stderr)
        print("  Move it under Design/, Docs/ or Scripts/, or add it to ROOT_ENTRIES on purpose.",
              file=sys.stderr)
        sys.exit(1)
    print("root_layout_audit: root is clean")


if __name__ == "__main__":
    main()
