#!/usr/bin/env python3
"""Counts text comparisons that decide word identity by shape, and stops the count ever rising."""

import argparse
import json
import os
import re
import sys

ROOTS = ("Sources",)
BASELINE = os.path.join("Scripts", "loose_match_baseline.json")

# A slice this short is a stem standing in for a word; a longer one is a truncation for display.
STEM_WIDTH = 8

# An argument that is a literal asks about a marker the code names, not about a word it was given.
LITERAL = r"""["']"""

# A fixed-width prefix on the same line as a text comparison: `hasPrefix(typed.prefix(2))`.
PREFIX_COMPARED = re.compile(
    r"\.prefix\(([0-9]+)\)(?=.*(?:hasPrefix\(|hasSuffix\(|==|!=))"
    r"|(?:hasPrefix\(|hasSuffix\(|==|!=).*\.prefix\(([0-9]+)\)"
)

# A fixed-width prefix kept as a String, which is a stem being named: `String(word.prefix(3))`.
PREFIX_KEPT = re.compile(r"String\([^()]*\.prefix\(([0-9]+)\)\)")

# A named width bounding an operand of a text comparison: `word.prefix(openingLettersShared) == ...`.
NAMED_PREFIX = re.compile(
    r"\.(?:prefix|suffix)\(\s*([A-Za-z_$][\w$]*)\s*\)\)*\s*(?:==|!=)"
    r"|(?:==|!=|hasPrefix\(|hasSuffix\()\s*(?:String\()?[\w$.]*\.(?:prefix|suffix)"
    r"\(\s*([A-Za-z_$][\w$]*)\s*\)"
)

# A width declared as a literal integer, which is the only kind the audit can judge.
WIDTH_DECLARATION = re.compile(r"\blet\s+([A-Za-z_$][\w$]*)\s*(?::\s*Int\s*)?=\s*([0-9]+)\b")


class UnresolvedWidth(Exception):
    """A named width bounds a comparison and no literal declaration says how wide it is."""

# A suffix table is a set of endings, not a whole-word equality test.
SUFFIX_TABLE = re.compile(r"(?:\w+Endings|endings)\.map\s*\{[^}]*\+\s*\$0")

# Repeated-letter collapse changes a word's spelling before comparing it.
REPEAT_COLLAPSE = re.compile(
    r"(?:withoutStammers|collapseRepeats|deduplicateRepeats|removeRepeated)\w*"
)

# Asking a collection of strings whether any of them swallows mine: `pool.contains(where: { $0.contains(word) })`.
SWALLOWS = re.compile(
    r"\.(?:contains|first|firstIndex|last|lastIndex|allSatisfy|filter)"
    r"\((?:where: *)?\{[^}]*\$0\.(?:contains|hasPrefix|hasSuffix)\( *(?!" + LITERAL + r")[A-Za-z$_]"
)


def findings_in(path):
    """Yields (line_number, tell, text) for every loose word match in the file."""
    with open(path, errors="ignore") as source:
        lines = source.read().split("\n")
    for number, line in enumerate(lines, start=1):
        code = line.split("//")[0]
        for match in PREFIX_COMPARED.finditer(code):
            width = int(match.group(1) or match.group(2))
            if width <= STEM_WIDTH:
                yield number, "a fixed-width prefix decides a text comparison", line.strip()
        for match in PREFIX_KEPT.finditer(code):
            if int(match.group(1)) <= STEM_WIDTH:
                yield number, "a fixed-width prefix is kept as a word", line.strip()
        for match in NAMED_PREFIX.finditer(code):
            name = match.group(1) or match.group(2)
            if declared_width(name, f"{path}:{number}") <= STEM_WIDTH:
                yield number, "a named short width bounds a text comparison", line.strip()
                break
        if SUFFIX_TABLE.search(code):
            yield number, "a suffix table decides a text comparison", line.strip()
        if REPEAT_COLLAPSE.search(code) or (
            re.search(r"\.key\s*!=\s*\$0\.element\.key", code)
            and re.search(r"enumerated\(\)\.filter", code)
        ):
            yield number, "repeated letters are collapsed before a text comparison", line.strip()
        if SWALLOWS.search(code):
            yield number, "a word is matched by being swallowed by another", line.strip()


def declared_widths():
    """Maps each literal integer declared under ROOTS to its smallest value, read in Python so no tool can be missing."""
    widths = {}
    for path in swift_files():
        with open(path, errors="ignore") as source:
            for name, value in WIDTH_DECLARATION.findall(source.read()):
                widths[name] = min(int(value), widths.get(name, int(value)))
    return widths


def declared_width(name, where):
    """Returns the declared width of `name`, and fails rather than guess when there is none."""
    widths = declared_widths()
    if name not in widths:
        raise UnresolvedWidth(f"{where}: no `let {name} = <integer>` under {', '.join(ROOTS)}")
    return widths[name]


def swift_files():
    for root in ROOTS:
        for directory, _, names in os.walk(root):
            if ".build" in directory or ".claude" in directory:
                continue
            for name in sorted(names):
                if name.endswith(".swift"):
                    yield os.path.join(directory, name)


def survey():
    counts, detail = {}, []
    for path in swift_files():
        found = list(findings_in(path))
        if found:
            counts[path] = len(found)
            detail += [(path, line, tell, text) for line, tell, text in found]
    return counts, detail


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true", help="record the current counts")
    parser.add_argument(
        "--after-merge",
        action="store_true",
        help="with --update, accept counts that rose because main moved underneath",
    )
    parser.add_argument("--report", action="store_true", help="list what is left, with the line")
    arguments = parser.parse_args()

    try:
        counts, detail = survey()
    except UnresolvedWidth as unresolved:
        print(f"Cannot judge a named width, so the audit fails rather than pass it: {unresolved}")
        return 2
    total = sum(counts.values())

    if arguments.report:
        for path, line, tell, text in detail:
            print(f"{path}:{line}  {tell}\n    {text}")
        print(f"\n{total} loose word matches in {len(counts)} files")
        return 0

    baseline = json.load(open(BASELINE)) if os.path.exists(BASELINE) else {}

    if arguments.update:
        recorded = baseline.get("files", {})
        # With a baseline, a file it does not list was clean, so any count there is a rise.
        risen = {
            path: (recorded.get(path, 0), count)
            for path, count in counts.items()
            if baseline and count > recorded.get(path, 0)
        }
        if risen and not arguments.after_merge:
            print("Refusing to record a higher count. The baseline only goes down.")
            for path, (was, now) in sorted(risen.items()):
                print(f"  {path}: {was} -> {now}")
            print("\nIf these arrived from main rather than from your own work, re-record")
            print("with --after-merge. The rise then shows in the baseline's diff, where a")
            print("reviewer can see it, rather than passing unremarked.")
            return 1
        if risen:
            print("Absorbing counts that rose with main. Each is a match to tighten later:")
            for path, (was, now) in sorted(risen.items()):
                print(f"  {path}: {was} -> {now}")
        json.dump(
            {"total": total, "files": counts}, open(BASELINE, "w"), indent=2, sort_keys=True
        )
        print(f"Recorded {total} loose word matches across {len(counts)} files.")
        return 0

    if not baseline:
        print(f"No baseline at {BASELINE}. Run: python3 {sys.argv[0]} --update")
        return 1

    recorded = baseline.get("files", {})
    failures = [
        f"{path}:{line}  {tell}\n    {text}"
        for path, line, tell, text in detail
        if counts[path] > recorded.get(path, 0)
    ]

    if failures:
        print("A word is the same word by its form, not by its shape.")
        print("These files gained a text comparison that decides identity by shape:\n")
        for failure in failures:
            print(f"  {failure}")
        print("\nAsk MeaningPreservationGuard.sameForm whether two spellings are one word,")
        print("spelledInto or isWritten whether it is written out, and WordErrorRate.measure")
        print("whether it is still there in order. See issue #189 in PLAN.md.")
        return 1

    print(f"Word matches: {total} loose, none higher than the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
