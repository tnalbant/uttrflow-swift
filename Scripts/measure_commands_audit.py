#!/usr/bin/env python3
"""Fails when Docs/measure-a-change.md names a command the tree does not have."""
import re
import sys
import tempfile
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
PAGE = Path("Docs/measure-a-change.md")
TOOLS = ("uttrflow-eval", "uttrflow-dev", "uttrflow-bakeoff")


def code_spans(text):
    """Every inline code span and every line of every fenced block."""
    spans = []
    fenced = False
    for line in text.splitlines():
        if line.strip().startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            spans.append(line)
        else:
            spans.extend(re.findall(r"`([^`]+)`", line))
    return spans


def make_targets(root):
    makefile = (root / "Makefile").read_text(errors="ignore")
    return set(re.findall(r"^([A-Za-z0-9_-]+):", makefile, re.MULTILINE))


def kebab(name):
    return re.sub(r"(?<!^)(?=[A-Z])", "-", name).lower()


def tool_commands(root, tool):
    """Subcommand names a tool answers to: explicit names plus ArgumentParser's default from the type."""
    names = set()
    for source in (root / "Sources" / tool).glob("*.swift"):
        text = source.read_text(errors="ignore")
        names.update(re.findall(r'commandName:\s*"([^"]+)"', text))
        names.update(kebab(n) for n in re.findall(r"struct\s+(\w+)\s*:[^{]*ParsableCommand", text))
    return names


def findings(root, page):
    text = (root / page).read_text(errors="ignore")
    targets = make_targets(root)
    problems = []
    named = 0
    for span in code_spans(text):
        for target in re.findall(r"\bmake\s+([A-Za-z0-9_-]+)", span):
            named += 1
            if target not in targets:
                problems.append(f"make {target}: no such Makefile target")
        for script in re.findall(r"\b(Scripts/[A-Za-z0-9_./-]+)", span):
            named += 1
            if not (root / script).is_file():
                problems.append(f"{script}: no such file")
        for tool, sub in re.findall(r"\b(uttrflow-eval|uttrflow-dev|uttrflow-bakeoff)\s+([a-z][a-z-]*)", span):
            named += 1
            if sub not in tool_commands(root, tool):
                problems.append(f"{tool} {sub}: no such subcommand in Sources/{tool}")
    if named == 0:
        problems.append(f"{page} names no command, so this audit checked nothing")
    return problems


def self_test():
    with tempfile.TemporaryDirectory() as work:
        root = Path(work)
        (root / "Docs").mkdir()
        (root / "Scripts").mkdir()
        (root / "Sources" / "uttrflow-dev").mkdir(parents=True)
        (root / "Makefile").write_text("bakeoff: ## x\n\techo\n")
        (root / "Scripts" / "soak.sh").write_text("")
        (root / "Sources" / "uttrflow-dev" / "Bench.swift").write_text("struct Bench: AsyncParsableCommand {}\n")
        (root / PAGE).write_text("Run `make bakeoff` or `Scripts/soak.sh`.\n```\nuttrflow-dev bench jobs.tsv\n```\n")
        good = findings(root, PAGE)
        (root / PAGE).write_text("Run `make bakeof`, `Scripts/gone.sh` and `uttrflow-dev benchmark`.\n")
        bad = findings(root, PAGE)
    if good or len(bad) != 3:
        print(f"measure-a-change self-test failed: good={good} bad={bad}", file=sys.stderr)
        return 1
    return 0


def main():
    if "--self-test" in sys.argv[1:] and self_test() != 0:
        return 1
    problems = findings(PACKAGE_ROOT, PAGE)
    for problem in problems:
        print(f"{PAGE}  {problem}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
