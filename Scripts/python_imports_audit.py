#!/usr/bin/env python3
"""Refuses a Python import under Scripts/ that is neither standard library, a repository module, nor pinned."""

import ast
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(REPO, "Scripts")
ALLOW = os.path.join(SCRIPTS, "python_imports_allow.txt")
LOCK = os.path.join(SCRIPTS, "requirements.lock")
ALLOW_LINE = re.compile(
    r"^(?P<module>[A-Za-z_][\w]*)\s+(?P<package>[A-Za-z0-9._-]+)==(?P<version>\S+)"
    r"\s+sha256:(?P<sha>[0-9a-f]{64})\s+(?P<licence>\S+)$"
)


def python_files(root):
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            if name.endswith(".py"):
                yield os.path.join(directory, name)


def sibling_modules(path):
    directory = os.path.dirname(path)
    names = set()
    for name in os.listdir(directory):
        if name.endswith(".py"):
            names.add(name[:-3])
        elif os.path.isfile(os.path.join(directory, name, "__init__.py")):
            names.add(name)
    return names


def repository_modules():
    listed = subprocess.run(["git", "-C", REPO, "ls-files", "*.py"], capture_output=True, text=True, check=True)
    return {os.path.splitext(os.path.basename(path))[0] for path in listed.stdout.split()}


def imports_in(path):
    with open(path, encoding="utf-8") as file:
        tree = ast.parse(file.read(), filename=path)
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                yield node.lineno, alias.name.split(".")[0]
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            yield node.lineno, node.module.split(".")[0]


def read_allow(path):
    entries, problems = {}, []
    if not os.path.exists(path):
        return entries, problems
    with open(path, encoding="utf-8") as file:
        for number, raw in enumerate(file, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            match = ALLOW_LINE.match(line)
            if match is None:
                problems.append(f"{path}:{number}: want 'module package==version sha256:<64 hex> licence'")
            else:
                entries[match["module"]] = match
    return entries, problems


def lock_problems(entries, lock_path):
    if not entries:
        return []
    if not os.path.exists(lock_path):
        return [f"{lock_path}: missing; every allowed import needs a hashed pin here"]
    with open(lock_path, encoding="utf-8") as file:
        text = file.read().replace("\\\n", " ")
    problems = []
    for entry in entries.values():
        pin = f"{entry['package']}=={entry['version']}"
        lines = [line for line in text.splitlines() if line.strip().lower().startswith(pin.lower())]
        if not any(f"--hash=sha256:{entry['sha']}" in line for line in lines):
            problems.append(f"{lock_path}: no '{pin} --hash=sha256:{entry['sha']}' line")
    return problems


def audit(root=SCRIPTS, allow_path=ALLOW, lock_path=LOCK):
    entries, problems = read_allow(allow_path)
    stdlib = set(sys.stdlib_module_names) | {"__future__"}
    first_party = repository_modules()
    for path in python_files(root):
        local = sibling_modules(path) | first_party
        for line, module in imports_in(path):
            if module not in stdlib and module not in local and module not in entries:
                problems.append(f"{os.path.relpath(path, REPO)}:{line}: third-party import '{module}' has no pin in {os.path.relpath(allow_path, REPO)}")
    return problems + lock_problems(entries, lock_path)


def main():
    problems = audit()
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print("python-imports-audit: FAIL. Use the standard library, or pin the package (see Docs/python-scripts.md).", file=sys.stderr)
        return 1
    print("python-imports-audit: every Scripts/ import is standard library, a repository module, or pinned.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
