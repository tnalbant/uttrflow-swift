#!/usr/bin/env python3
"""Keep Dependabot's automatically created default labels enabled."""

from pathlib import Path
import re
import sys


CONFIG = Path(__file__).resolve().parents[1] / ".github" / "dependabot.yml"


def main() -> int:
    text = CONFIG.read_text(encoding="utf-8")
    entries = re.findall(
        r"(?ms)^  - package-ecosystem: [^\n]+\n(.*?)(?=^  - package-ecosystem:|\Z)",
        text,
    )
    if len(entries) != 2:
        print(f"expected two Dependabot update entries, found {len(entries)}", file=sys.stderr)
        return 1
    for entry in entries:
        if re.search(r"(?m)^    labels:", entry):
            print("Dependabot labels override its automatically created defaults", file=sys.stderr)
            return 1
    print("Dependabot update entries leave automatic default labels enabled")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
