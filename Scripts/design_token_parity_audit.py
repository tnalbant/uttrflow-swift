#!/usr/bin/env python3
"""Fails when a shared artboard surface/text token drifts from BrandPalette.swift.

`Design/_gen_common.py` and `Design/_gen_shell.py` declare the page, card, rail, control,
separator and primary/muted/dim text colours every artboard inherits. `BrandPalette.swift`
is the single source of truth for the same roles in the shipped app (see
`Docs/app-main-window.md`). Nothing ties the two together, so #1162 found all 73 artboards
still drawing 2026-era system greys years after the shipped UI moved to `BrandPalette`.

This reads both sides and fails on any hex mismatch, light or dark, so a change to one
without the other is caught here rather than by the next person who compares screenshots.
"""

import argparse
import os
import re
import sys


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, ".."))
PALETTE_SOURCE = os.path.join(REPO_ROOT, "Sources", "Uttrflow", "Brand", "BrandPalette.swift")
COMMON_SOURCE = os.path.join(REPO_ROOT, "Design", "_gen_common.py")
SHELL_SOURCE = os.path.join(REPO_ROOT, "Design", "_gen_shell.py")

# A role name to the `static let` it is declared under in BrandPalette.swift, and the
# `--token` name it must match in the light-root / dark-`.theme-dark` generator blocks.
ROLES = (
    ("Surface.ground", "ground", "window-bg"),
    ("Surface.card", "card", "card-bg"),
    ("Surface.control", "control", "control-bg"),
    ("Surface.rail", "rail", "sidebar-bg"),
    ("Line.separator", "separator", "separator"),
    ("Text.primary", "primary", "label"),
    ("Text.muted", "muted", "label-2"),
    ("Text.dim", "dim", "label-3"),
)

SWIFT_UINT32 = re.compile(r"0x([0-9A-Fa-f_]{6,8})")
SWIFT_TONE = re.compile(
    r"static let (?P<name>\w+)(?::\s*UInt32)?\s*=\s*"
    r"(?:BrandTone\(\s*dark:\s*(?P<dark>[^,]+),\s*light:\s*(?P<light>[^,)]+)[^)]*\)"
    r"|(?P<fixed>0x[0-9A-Fa-f_]+))"
)
TOKEN_LINE = r"--{name}:\s*(?P<hex>#[0-9A-Fa-f]{{6}});"


def normalize_hex(value):
    """`0x0B_0C10` or `#0B0C10` -> `0b0c10`, lowercase, no separators."""
    value = value.strip().lstrip("#").replace("0x", "").replace("_", "")
    return value.lower()


def load_palette(path):
    """Parse every `static let` BrandPalette declares, resolving identifier references.

    Returns {name: (dark_hex, light_hex)}, both normalized. A fixed (non-`BrandTone`) value
    carries the same hex in both slots, matching `BrandTone.init(_:)`.
    """
    text = open(path).read()
    values = {}
    for match in SWIFT_TONE.finditer(text):
        name = match.group("name")
        if match.group("fixed"):
            hex_value = normalize_hex(match.group("fixed"))
            values[name] = (hex_value, hex_value)
            continue
        dark_raw = match.group("dark").strip()
        light_raw = match.group("light").strip()
        dark = values[dark_raw][0] if dark_raw in values else normalize_hex(dark_raw)
        light = values[light_raw][1] if light_raw in values else normalize_hex(light_raw)
        values[name] = (dark, light)
    return values


def load_token(path, name):
    text = open(path).read()
    match = re.search(TOKEN_LINE.format(name=re.escape(name)), text)
    if not match:
        raise SystemExit(f"design token parity audit: no --{name} declaration found in {path}")
    return normalize_hex(match.group("hex"))


def load_theme_dark_block(path):
    text = open(path).read()
    start = text.find(".theme-dark {")
    if start == -1:
        raise SystemExit(f"design token parity audit: no .theme-dark block found in {path}")
    end = text.find("\n    }", start)
    return text[start:end]


def audit_pairs():
    if not os.path.isfile(PALETTE_SOURCE):
        raise SystemExit(f"design token parity audit: {PALETTE_SOURCE} not found")
    palette = load_palette(PALETTE_SOURCE)

    dark_block = load_theme_dark_block(SHELL_SOURCE)
    rows = []
    for swift_name, role, token in ROLES:
        if role not in palette:
            raise SystemExit(
                f"design token parity audit: BrandPalette has no '{role}' role "
                f"(expected {swift_name}); update ROLES if it was renamed"
            )
        palette_dark, palette_light = palette[role]

        # `card-bg` and `control-bg` are declared in _gen_shell.py, not _gen_common.py.
        light_source = SHELL_SOURCE if token in ("card-bg", "control-bg") else COMMON_SOURCE
        light_hex = load_token(light_source, token)

        dark_match = re.search(TOKEN_LINE.format(name=re.escape(token)), dark_block)
        if not dark_match:
            raise SystemExit(
                f"design token parity audit: no --{token} override in .theme-dark of {SHELL_SOURCE}"
            )
        dark_hex = normalize_hex(dark_match.group("hex"))

        rows.append((swift_name, token, "light", palette_light, light_hex))
        rows.append((swift_name, token, "dark", palette_dark, dark_hex))
    return rows


def self_test():
    palette = load_palette(PALETTE_SOURCE) if os.path.isfile(PALETTE_SOURCE) else {}
    ok = True
    if "raised" not in palette or "control" not in palette:
        print("  ✗ self-test: BrandPalette parse did not resolve Surface.control", file=sys.stderr)
        ok = False
    elif palette["control"][0] != palette["raised"][0]:
        print(
            "  ✗ self-test: Surface.control's dark tone should resolve to Surface.raised",
            file=sys.stderr,
        )
        ok = False
    return ok


def audit():
    rows = audit_pairs()
    print("Shared artboard tokens vs BrandPalette.swift")
    failures = []
    for swift_name, token, theme, palette_hex, generator_hex in rows:
        verdict = "pass" if palette_hex == generator_hex else "FAIL"
        print(f"  {swift_name:<16} {theme:<5} --{token:<12} palette #{palette_hex}  generator #{generator_hex}  [{verdict}]")
        if palette_hex != generator_hex:
            failures.append((swift_name, token, theme, palette_hex, generator_hex))

    if failures:
        print(
            f"\n  ✗ {len(failures)} shared artboard token(s) disagree with BrandPalette.swift:",
            file=sys.stderr,
        )
        for swift_name, token, theme, palette_hex, generator_hex in failures:
            print(
                f"    {swift_name} ({theme}): palette #{palette_hex}, "
                f"generator --{token} #{generator_hex}",
                file=sys.stderr,
            )
        print(
            "    Update the generator token in Design/_gen_common.py or Design/_gen_shell.py to\n"
            "    match BrandPalette.swift, then regenerate every artboard.",
            file=sys.stderr,
        )
        return 1

    print(f"\ndesign token parity audit: all {len(rows)} shared artboard tokens match BrandPalette.swift.\n")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="prove BrandPalette.swift parsing resolves an identifier reference correctly",
    )
    options = parser.parse_args()

    if options.self_test:
        if not self_test():
            print(
                "\ndesign token parity audit: self-test failed; the Swift parser is broken.\n",
                file=sys.stderr,
            )
            return 1
        return 0

    return audit()


if __name__ == "__main__":
    sys.exit(main())
