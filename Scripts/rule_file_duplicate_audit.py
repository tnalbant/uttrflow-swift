#!/usr/bin/env python3
"""Find repeated headings and exact repeated sentences in the repository rule files."""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path


RULE_FILES = ("AGENTS.md", "Docs/agents/*.md")
HEADING = re.compile(r"^ {0,3}(#{1,6})\s+(.+?)\s*#*\s*$")
FENCE = re.compile(r"^\s*(```+|~~~+)")
SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[A-Z0-9\"'`])")
MARKDOWN = re.compile(r"[`*_~]")
NORMATIVE = re.compile(r"\b(?:must|must not|should|should not|shall|may not|never|always|do not|don't)\b")


def canonical(text: str) -> str:
    """Normalize whitespace and Markdown emphasis without changing word identity."""
    return " ".join(MARKDOWN.sub("", text).split()).casefold()


def rule_paths(root: Path) -> list[Path]:
    paths = [root / "AGENTS.md", *sorted((root / "Docs/agents").glob("*.md"))]
    return [path for path in paths if path.is_file()]


def headings(path: Path) -> list[tuple[str, int]]:
    found: list[tuple[str, int]] = []
    for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        match = HEADING.match(line)
        if match:
            found.append((canonical(match.group(2)), number))
    return found


def sentences(path: Path) -> list[tuple[str, int]]:
    found: list[tuple[str, int]] = []
    paragraph: list[str] = []
    start = 0
    fenced = False

    def flush() -> None:
        nonlocal paragraph
        if not paragraph:
            return
        text = " ".join(part.strip() for part in paragraph)
        for sentence in SENTENCE_SPLIT.split(text):
            normalized = canonical(sentence).strip(" .!?;:")
            if normalized and NORMATIVE.search(normalized):
                found.append((normalized, start))
        paragraph = []

    for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if FENCE.match(line):
            flush()
            fenced = not fenced
            continue
        if fenced:
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith("|") or HEADING.match(line):
            flush()
            continue
        if stripped.startswith(">"):
            stripped = stripped.lstrip("> ")
        stripped = re.sub(r"^\s*(?:[-*+]\s+|\d+[.)]\s+)", "", stripped)
        if not paragraph:
            start = number
        paragraph.append(stripped)
    flush()
    return found


def scan(root: Path) -> tuple[list[str], list[str]]:
    heading_locations: dict[tuple[Path, str], list[int]] = defaultdict(list)
    sentence_locations: dict[str, dict[Path, list[int]]] = defaultdict(lambda: defaultdict(list))
    paths = rule_paths(root)

    for path in paths:
        for title, line in headings(path):
            heading_locations[(path, title)].append(line)
        for sentence, line in sentences(path):
            sentence_locations[sentence][path].append(line)

    duplicate_headings = [
        f"{path.relative_to(root)}:{lines[1]}: repeated heading '{title}' (first at line {lines[0]})"
        for (path, title), lines in heading_locations.items()
        if len(lines) > 1
    ]
    duplicate_rules = [
        f"{path.relative_to(root)}:{lines[0]}: repeats rule sentence from "
        f"{first_path.relative_to(root)}:{first_lines[0]}: {sentence}"
        for sentence, by_path in sentence_locations.items()
        if len(by_path) > 1
        for first_path, first_lines in [next(iter(by_path.items()))]
        for path, lines in list(by_path.items())[1:]
    ]
    return duplicate_headings, duplicate_rules


def self_test() -> int:
    import tempfile

    with tempfile.TemporaryDirectory(prefix="uttrflow-rule-duplicates-") as temporary:
        root = Path(temporary)
        (root / "Docs/agents").mkdir(parents=True)
        (root / "AGENTS.md").write_text(
            "# Policy\n\n## Boundaries\n\n- You must keep every change reviewable.\n\n## Boundaries\n"
        )
        (root / "Docs/agents/workflow.md").write_text(
            "## Boundaries\n\nYou must keep every change reviewable.\n"
        )
        headings_found, rules_found = scan(root)
        if not any("repeated heading 'boundaries'" in item for item in headings_found):
            print("duplicate rule-file audit self-test: repeated heading was missed", file=sys.stderr)
            return 1
        if not any("repeats rule sentence" in item for item in rules_found):
            print("duplicate rule-file audit self-test: repeated rule sentence was missed", file=sys.stderr)
            return 1

        (root / "Docs/agents/workflow.md").write_text(
            "## Workflow\n\nYou should keep every change reviewable today.\n"
        )
        (root / "AGENTS.md").write_text(
            "# Policy\n\n## Boundaries\n\nYou must keep every change reviewable.\n"
        )
        headings_found, rules_found = scan(root)
        if headings_found or rules_found:
            print("duplicate rule-file audit self-test: distinct text was flagged", file=sys.stderr)
            return 1
    print("duplicate rule-file audit self-test: passed")
    return 0


def main() -> int:
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    if sys.argv[1:]:
        print(f"usage: {Path(sys.argv[0]).name} [--self-test]", file=sys.stderr)
        return 2
    root = Path(__file__).resolve().parent.parent
    duplicate_headings, duplicate_rules = scan(root)
    findings = [*duplicate_headings, *duplicate_rules]
    if findings:
        print("Rule-file duplicates found:")
        for finding in findings:
            print(f"  {finding}")
        return 1
    print("Rule-file duplicate audit passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
