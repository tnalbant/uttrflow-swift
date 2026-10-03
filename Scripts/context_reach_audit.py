#!/usr/bin/env python3
"""Refuses a context module that reads text by synthetic copy, posted keys, screen capture or text recognition.

Context is read through Accessibility only. The rejected routes and their cost are in
Docs/context-accessibility.md under "Text an application does not publish is not read".

Usage:  python3 Scripts/context_reach_audit.py             (belongs in `make verify`)
        python3 Scripts/context_reach_audit.py --self-test   also proves a forbidden call is caught
"""
import argparse
import re
import sys
import tempfile
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parent.parent

CONTEXT_MODULES = ("Sources/UttrflowContext",)

FORBIDDEN = {
    "the clipboard": re.compile(r"\b(NSPasteboard|UIPasteboard)\b"),
    "a posted key or mouse event": re.compile(
        r"\b(CGEventPost|CGEventPostToPid|CGEventCreateKeyboardEvent)\b"
        r"|\bCGEvent\s*\(\s*keyboardEventSource\b|\.post(ToPid)?\s*\(\s*(tap|_)"
    ),
    "screen capture": re.compile(
        r"\b(ScreenCaptureKit|SCStream|SCScreenshotManager|SCShareableContent|"
        r"CGWindowListCreateImage|CGDisplayCreateImage|CGPreflightScreenCaptureAccess|"
        r"CGRequestScreenCaptureAccess)\b"
    ),
    "text recognition": re.compile(r"\bimport\s+Vision(Kit)?\b|\bVNRecognizeTextRequest\b|\bRecognizeTextRequest\b"),
}


def offences(root):
    """Returns (path, line number, reason) for every forbidden call in the context modules."""
    found = []
    for module in CONTEXT_MODULES:
        directory = Path(root) / module
        if not directory.is_dir():
            found.append((module, 0, "the module this audit guards is gone"))
            continue
        for path in sorted(directory.rglob("*.swift")):
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                for reason, pattern in FORBIDDEN.items():
                    if pattern.search(line):
                        found.append((str(path.relative_to(root)), number, reason))
    return found


def self_test():
    """Proves the audit passes a clean module and catches one call of each forbidden kind."""
    print("context_reach_audit self-test")
    samples = {
        "the clipboard": "let text = NSPasteboard.general.string(forType: .string)",
        "a posted key or mouse event": "event?.post(tap: .cghidEventTap)",
        "screen capture": "import ScreenCaptureKit",
        "text recognition": "let request = VNRecognizeTextRequest()",
    }
    with tempfile.TemporaryDirectory() as scratch:
        module = Path(scratch) / CONTEXT_MODULES[0]
        module.mkdir(parents=True)
        source = module / "Reader.swift"
        source.write_text("import ApplicationServices\nlet value = AXUIElementCreateSystemWide()\n")
        assert offences(scratch) == [], "a module that reads through Accessibility must pass"
        for reason, line in samples.items():
            source.write_text(f"import Foundation\n{line}\n")
            found = offences(scratch)
            assert [r for _, _, r in found] == [reason], f"{line!r} must be caught as {reason}, got {found}"
    print("ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    found = offences(PACKAGE_ROOT)
    if found:
        print("context_reach_audit: the context modules reach past Accessibility:", file=sys.stderr)
        for path, number, reason in found:
            print(f"  {path}:{number}: {reason}", file=sys.stderr)
        print("  Read context through Accessibility only; see Docs/context-accessibility.md.",
              file=sys.stderr)
        sys.exit(1)
    print("context_reach_audit: context is read through Accessibility only")


if __name__ == "__main__":
    main()
