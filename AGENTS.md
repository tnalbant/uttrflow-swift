# AGENTS.md

Uttrflow is dictation software for macOS with a clipboard and AI suggestions built in, entirely
on-device. This file is the entry point for every agent (Claude, Codex, Cursor, Copilot, any other) and every
contributor. `CLAUDE.md`, `.cursor/rules/` and `.github/copilot-instructions.md` only point
here.

Each rule states a measure, a limit and the command that checks it. "Pass" means exit 0. The
rules are split by concern; read the file for the work you are doing before you start it.

## Read first

1. This file.
2. `AGENTS.local.md`, if it exists. It is private and gitignored; see
   [public-boundary](Docs/agents/public-boundary.md#local-rules-file).
3. The file below that matches your work.
4. [`Docs/README.md`](Docs/README.md), then the page for the module you change.

| You are... | Read |
|---|---|
| writing or changing code, tests or comments | [Docs/agents/code-quality.md](Docs/agents/code-quality.md) |
| changing what dictation, the clipboard or the data stores do | [Docs/agents/product.md](Docs/agents/product.md) |
| branching, committing, opening or cleaning up after a pull request | [Docs/agents/workflow.md](Docs/agents/workflow.md) |
| writing any text that will be committed, pushed or posted | [Docs/agents/public-boundary.md](Docs/agents/public-boundary.md) |
| hitting a tooling failure | [Docs/tooling-traps.md](Docs/tooling-traps.md) |

## Commands

```bash
make verify        # the whole gate: audits, lint, build, tests, coverage, offline audit
make lint          # style and documentation violations
make format        # rewrite sources in canonical style
make build         # compile every module
make test          # run the test suite
swift test --filter <TestCase>   # one test case or method, the fast loop
make coverage      # tests plus the per-module coverage floor
make bakeoff       # score every clean-up engine against the corpus
make hooks         # install the commit-msg and pre-push gates (once per clone)
make app-hardened  # a build fit to test on another Mac
```

Run `make verify` before every push; CI runs the same command. Each target's one-line
description is in the `Makefile`. `PLAN.md` is the live phase tracker.

## Layout

- `Sources/`: one SwiftPM target per module (`Uttrflow*`) plus the `uttrflow-dev`,
  `uttrflow-eval` and `uttrflow-bakeoff` tools. `Tests/` mirrors it.
- `Docs/`: a page per subsystem, holding the measurements, platform traps and rejected
  approaches the code cannot say for itself.
- `Scripts/`: audits, release and packaging. `Design/`: design canvases. `Resources/`: bundle
  resources and `Uttrflow-Info.plist`.
- `uttrflow-backend`, `uttrflow-fe` and `uttrflow-panel` are separate repositories. This one
  never reaches into them.

## Hard gates

Every row is checked by a command. Breaking one is a bug whatever it improves.

| Gate | Limit | Command |
|---|---|---|
| Comment block length | 1 line | `make comment-audit` |
| Coverage per module | at least 95% | `make coverage` |
| Force unwraps, `try!`, implicitly unwrapped optionals | 0 | `make lint` |
| Compiler warnings | 0 | `make build` |
| Spelling matches decided by shape | never rises | `make match-audit` |
| Real personal data in fixtures | 0 | `make pii-audit` |
| Connections on the dictation path | 0 | `make offline-audit` |
| Session-only text in a tracked file, commit or PR | 0 | `make disclosure-audit` |
| Docs contradict the tree; history or numbers in rule files | 0 | `make docs-audit` |
| Failing or pending checks when a PR is called done | 0 | `gh pr checks` |
| Commits behind `origin/main` when the PR opens | 0 | `git rev-list --count HEAD..origin/main` |
| Agent commits on `main`, tags, or direct pushes to it | 0 | ruleset, `git log origin/main..main` |
| Worktrees, branches, processes left by a session | 0 | `git worktree list` |

## Working agreement

1. **Surgical.** `git diff --stat origin/main` lists only files the task needs; 0 drive-by edits.
   0 behaviour-neutral reformatting, renames or reflows outside the lines the task changes.
   Anything else you notice becomes a follow-up in the PR, not a change.
2. **Goal first.** Before coding, write the success check: one command and its expected result.
3. **No invention.** 0 invented APIs, defaults or behaviours: read the code or run it before
   stating a fact about it.
4. **Honest reports.** Every "passes" or "works" cites the command and its exit code. List each
   check you did not run, and why. 0 claims without evidence.
5. **Assume, then say so.** Ask only for the triggers under "Ask first"; for anything else
   take the reasonable assumption and record it under "Assumed" in the PR.

## Boundaries

**Always**
- run `make verify` before every push and stage paths by name;
- work in a worktree cut from freshly fetched `origin/main`, and read `git status -sb` before the
  first edit so changes you did not make stay untouched;
- write the five PR fields and name the command behind every claim;
- run a change to input, insertion or context reading once in a real target app;
- capture a long command's output to a file once and read the file; rerunning the command to
  filter its output is 0.

**Ask first**: stop, report what you saw, and wait; never force-fix and never delete state to
make a command succeed.
- a commit on `main`, or a branch, worktree or pull request you did not create;
- a merge, rebase or cleanup you cannot complete cleanly;
- a secret, personal data or session-only text already committed or published;
- a gate that fails for a reason you cannot explain;
- a new workflow, a new dependency, a protected file, or a different promise in
  `Docs/definition-of-done.md`.

**Never**
- commit to `main`, tag, force-push, or skip a hook (`--no-verify`);
- raise a baseline (except the reported `--after-merge` case) or loosen a gate;
- add a `Co-Authored-By` trailer;
- commit a secret, personal data or session-only text;
- hand-edit a generated file;
- merge a pull request unless a maintainer says so for that pull request.

## What must never reach a tracked file

A tracked file, commit message, pull-request title or body, issue or code comment states
technical requirements and technical decisions, in the product's own words, and nothing else.
Run `python3 Scripts/disclosure_audit.py` before every commit; it must exit 0. Details, and
what to do when something is already committed:
[Docs/agents/public-boundary.md](Docs/agents/public-boundary.md).

## Changing these files

1. A new rule or gate names the mistake it prevents and has been seen to prevent it. Time
   pressure never waives a gate.
2. A new rule states a measure, a limit and a check command, or says it is judgement and names
   who checks it.
3. It is present tense. It carries 0 incidents, 0 dates, 0 issue or pull-request numbers and 0
   anecdotes; `make docs-audit` fails on dates and on issue or pull-request numbers. Evidence
   goes on a `Docs/` page, linked in one line.
4. It goes in the one file that owns it. A rule about a single module goes on that module's
   `Docs/` page or in a nested `AGENTS.md` beside the code. Do not add a competing rule here.
5. A rule that no longer prevents a mistake is deleted.
