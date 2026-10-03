# AGENTS.md

Uttrflow is a macOS clipboard manager with dictation built in, entirely on-device. This file is
the entry point for every agent (Claude, Codex, Cursor, Copilot, any other) and every
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
python3 Scripts/disclosure_audit.py --show-terms     # see the lists decoded
python3 Scripts/disclosure_audit.py --history        # every commit on every ref
make hooks                                           # install both git hooks
```

The ratchet refuses a rise, and there is one sanctioned way past it. A document that
states the rule has to name the category it forbids — this file says "competitor" six
times — so `--update-baseline --absorb` records a rise and prints every one of them,
which puts it in the baseline's diff where a reviewer sees it. Reach for it when the word
is the subject, never to make a paragraph fit.

**Never weaken this gate to make a commit pass**, and never add a path exemption to get
past it. There is exactly one exemption in the file — the evaluation corpus, from the
phrase patterns only, because a corpus of dictated English legitimately contains "churn
rate" — and it does not cover names. A failing gate is the gate working.

`--history` is what a repository is judged on before it is made public: a tree can be
cleaned in one commit, and history cannot be cleaned at all.

## Where this sits

Four pieces: this app, `uttrflow-backend` (Go on ECS, the only thing that touches the
server's database), `uttrflow-fe` (Next.js on ECS, the site), and `uttrflow-panel` (design
source). Infrastructure is shared with the open-llm AWS account; the data is not.

**Two databases, and they hold different things.** The server's holds an account: who
somebody is, what they have paid for, which machines are signed in. This app's local store
— under Application Support — holds the clipboard, the dictation history, the personal
dictionary and the snippets, and **none of it is ever sent anywhere**. Transcriptions are
local, full stop: the product's whole claim is that dictation happens on this Mac and stays
here. If that ever changes it is a product decision with a privacy page attached, not a
refactor.

Network access is not limited to the account backend: sign-in/session calls live in
`UttrflowAccount`, speech-model/tokenizer assets can be downloaded, and Sparkle checks for
and downloads app updates. The networking audit and its limits are recorded in
[`Docs/offline.md`](Docs/offline.md). Opt-in crash diagnostics also send scrubbed crash and
hang reports to Sentry from `UttrflowDiagnostics`; see [`Docs/crash-reporting.md`](Docs/crash-reporting.md)
for what is sent and why.

## What dictation is for — NON-NEGOTIABLE

**The goal is an accurate transcript of what the speaker said, cleaned of the noise of
speaking and laid out the way they would have typed it. It is not a rewrite.**

The tidier is a filter. It removes what was never meant as words — "um", "hmm", "aah",
stammers, false starts, the discarded half of a spoken self-correction — and adds what
speech leaves implicit: punctuation, question marks where a question was asked,
capitalisation, numerals, line and paragraph breaks, a list when the speaker plainly
spoke one. Every word the speaker meant survives, in their order and their register.

It never shortens, summarises, changes tone, swaps synonyms, reorders, answers, obeys,
or finishes a thought. Those are rewrites; a user who wants one asks for it, and it is
a different feature. `Docs/cleanup.md` is the catalogue — three tiers, what is done,
what is not yet, what is forbidden — and every change to the prompt or the rules is
measured against the corpus before it lands (`make bakeoff`). An agent proposing "make
the output more polished" is proposing a rewrite; the answer is no.

## Latin letters only — NON-NEGOTIABLE

**Uttrflow writes English/Latin script only. Hindi and Hinglish speech is romanised the way
people type it, never written in Devanagari and never translated.**

"हाँ ठीक है" is inserted as "Haan thik hai" — not in Devanagari, and not as "Yes, okay".
Uttrflow is not a translator. This binds every path that inserts dictated text: a model's
rewrite, the rules, and the untidied fallback. The Languages setting steers what recognition
listens for; it never chooses the output script. `Docs/latin-output.md` is how it is enforced
and measured: the romaniser the rules use, the guard that refuses a translation, and the last
check before insertion. A change that lets Devanagari or a translation reach the screen is a
bug, whatever it improves.

## No patchy fixes: root cause and long-term design — NON-NEGOTIABLE

**Find why the defect exists and fix that. A patch, a workaround or a special case is never
the answer here, however small the bug looks.**

1. **Root cause first.** Before changing code, say why the bug exists and why it was not
   caught. A fix that makes one symptom go away and leaves the cause in place is rejected.
2. **No special cases.** Nothing keyed to one phrase, one app, one fixture or one reported
   sentence. If a rule cannot be stated for the whole class of input, the design is wrong.
3. **Refactor what you meet.** Code that is the wrong shape for the change is reshaped into
   a clean seam first: SOLID, DRY, and no abstraction that nothing needs yet (YAGNI). A
   ground-up rewrite is acceptable when the evidence says the design cannot carry the
   change; lowering the quality of the code is not acceptable under any deadline.
4. **Measure before it lands.** A change to recognition, correction or cleanup is judged
   against the corpus (`make bakeoff`) and records the before and after.
5. **Extendable by default.** Ask what the next case of the same kind needs, and make that
   a data or configuration change rather than another branch in the code.
6. **One path per capability.** Never ship two implementations of the same job: two
   language models for tidying, two scorers, two seam deciders, two lexicons. When a choice
   is needed, measure the candidates against the corpus, keep one, and delete the other in
   the same pull request. Two parallel paths are a standing maintenance cost that no
   measurement ever pays back.

The pull request states the root cause and why it cannot recur; a description that only
says what changed is incomplete. This is a rule rather than a preference because a fix
that treats the symptom is cheap today and is paid for by every agent that works in that
file afterwards.

## Rules that are not preferences

**Never put a real email address or a real postal address in a fixture.** Use
`example.com` and an invented street; `Scripts/pii_audit.sh` fails the build on anything
else, and it runs first in `make verify` so you find out in two seconds rather than after
a build.

This is a rule because it has already happened twice. A stranger's real address — real
complex, real road, real pincode — was the sample expansion for the "my address" snippet
and had reached eleven files before anyone noticed; the owner's personal email was the
account fixture. Both looked exactly like the sample data around them, which is the whole
problem: fixture data has to look real to be useful, and the most available realistic
value is the one you can see from where you are sitting. **This repository is being
open-sourced, and a published address cannot be taken back by a later commit.**

**Never decide that two spellings are the same word by their shape.** Not a prefix of
*n* characters, not "is one of them a substring of the other". Ask
`MeaningPreservationGuard.sameForm` whether two spellings are one word, `spelledInto` or
`isWritten` whether a word is written out at its own boundaries, and
`WordErrorRate.measure` whether it is still there *in the order it was said*. Those are
the single home for each of those questions, and a local reimplementation is how this
goes wrong.

A shape match can only fail in one direction: it says "same" too easily, every one of
these sits on a path whose failure is *acceptance*, and an acceptance leaves no trace —
so the bug ships silently and no test that was written goes red. A three-character stem
let "confirm" become "confuse" and "Aarav" become "Aaron" past the guard whose entire job
is to refuse that; a two-character one decided whether a model had echoed the line.
`Scripts/loose_match_audit.py` counts these per file against
`Scripts/loose_match_baseline.json` and runs in `make verify`. It ratchets like the
comment and disclosure baselines: a count may fall and may never rise.

```bash
make match-report                                            # what is left, with the line
python3 Scripts/loose_match_audit.py --update                # re-record after tightening one
python3 Scripts/loose_match_audit.py --update --after-merge  # only when main moved under you
```

One match is baselined today, and it is the shape with a legitimate answer:
`CaretEchoPass` asks which completion targets begin with what the user has typed, where
a prefix is the question rather than a stand-in for one. That is what the baseline is
for — the audit reports the shape, and you say why this one is right.

**Do not do a `good first issue` yourself, and never take an issue somebody has claimed.**
Those labels are inventory for somebody else, not a task queue. Before opening a branch for
any issue, read its thread: if anyone outside has asked for it or said they are on it, it is
theirs — add the `claimed` label, reply, and find other work. If it carries `good first
issue` and nobody has claimed it, still leave it alone. `CONTRIBUTING.md` sets out what a
claim guarantees a contributor, and that is a promise this side has to keep. If a branch is
already open against one, take the label off the issue rather than leaving free work
advertised that is about to be closed underneath whoever picks it up.

This is a rule because the project has already broken it. #51 was labelled *good first
issue*; a first-time contributor asked for it on the thread and got no reply; a maintainer
branch opened shortly afterwards, did the same work as part of something larger, and closed
the issue on merge while their pull request (#62) sat unreviewed. A README section left
alone for a week costs nothing next to that.

**CI exists now, and it is `.github/workflows/`.** This reverses a rule that was absolute
in the private repository, so it is worth saying why rather than leaving two agents to
argue about it. The old rule was: never add a workflow, because macOS runners bill at ten
times Linux, this project cannot use Linux (it builds against macOS 26 frameworks and
drives the real Accessibility, clipboard and speech APIs), and fifty-one runs over two days
ate 97% of a month's included minutes — after which jobs stopped starting silently, for
days, while the repository went on looking green.

Every part of that is still true except the part that mattered: **a public repository does
not pay for standard runners.** The constraint was cost, the cost is gone, and the local
gate — `.githooks/pre-push`, installed with `make hooks` — is still worth having because it
is still the fastest answer.

The tracked workflows are CI (build and test), CodeQL (weekly static analysis), dependency
review (new dependency vulnerabilities and licences), Oracle sweep (exhaustive randomized
clipboard-reader tests, nightly and on related pull requests), Quality (disclosure, workflow,
spelling and link checks), Release (build and publish releases), Scorecard (supply-chain
posture), and Security (secret, workflow and dependency scans). Adding a workflow requires
explicit approval.

**Never run `git add -A`, `git add .`, or `git commit -a`.** More than one agent works in
this repository at once, and a blanket add sweeps another session's half-finished work
into your commit under your message. This has happened four times. Stage the paths you
touched, by name.

**Never rewrite pushed history, and never rebase while another session is committing.**
Check first: `ps aux | grep -c '[c]laude.*--add-dir'`.

**Rebase onto `origin/main` before opening the pull request.** `main` moves under you while
you work — it is where everything lands — so a branch cut this morning is behind by
lunchtime, and rebasing is what keeps the diff in the pull request the change you actually
made. Rebasing an unpushed branch is not rewriting pushed history,
so the rule above does not conflict with this one.

**Nothing an agent does touches `main` except through a pull request.** Not a direct
push, not a rebase onto it, not a tag, not a docs commit that seems too small to matter.
A ruleset blocks it at the server, so this is a description of what will happen rather
than a request. If you find yourself with a commit on `main`, stop and say so rather
than tidying it away.

**Commit messages carry no `Co-Authored-By` trailer.** Not for an agent, not for a tool.
The message says what the change does; who typed it is what `git log` already records.

**Merging is not reviewing.** Nobody else read the change, so the pull request is where
you write down what you would have wanted a reviewer to know: what was measured, what
was assumed, and what you are least sure of. A merge that ends the conversation is worse
than no merge at all.

## Building and releasing

`Docs/releasing.md` covers a release by hand; `RELEASING.md` covers the tag workflow. In short:

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
| Logic-module UI imports and platform dependencies | never rises | `make layering-audit` |
| Real personal data in fixtures | 0 | `make pii-audit` |
| Connections on the dictation path | 0 | `make offline-audit` |
| Session-only text in a tracked file, commit or PR | 0 | `make disclosure-audit` |
| Docs contradict the tree; history or numbers in rule files | 0 | `make docs-audit` |
| Failing or pending checks when a PR is called done | 0 | `gh pr checks` |
| Commits behind `origin/main` when the PR opens | 0 | `git rev-list --count HEAD..origin/main` |
| Agent commits on `main`, tags, or direct pushes to it | 0 | ruleset, `git log origin/main..main` |
| Worktrees, branches, processes left by a session | 0 | `git worktree list` |

## Mistakes that have already cost time

Each rule below prevents a mistake that is in this repository's code or history. One rule, one
line of evidence; the long form lives in the issue it came from.

1. **A rule names the command that fails when it is broken, or says it is unenforced.** A gate
   that cannot find its tool fails instead of passing, and a count quoted in this file is
   checked by running the script in the same commit. *Evidence:* `Scripts/loose_match_audit.py`
   skips its named-width check when `rg` is not on `PATH`, so the baseline count in this file
   can be false without anything going red.
2. **When `make verify` is red on `main`, the next merge is its repair.** *Evidence:* `ci.yml`
   failed in each of its last 300 runs on `main` (checked 2026-10-03).
3. **A key proposes; it never disposes.** A phonetic or other hash is a recall tool. Whether two
   spellings are one word is decided by `MeaningPreservationGuard.sameForm`, and a helper that
   compares letters is a shape match even when it hides inside a function. *Evidence:*
   `ReadingRestraint.opensAlike` (a two-letter prefix test) rejects v/w and th/t pairs the
   phonetic key had merged.
4. **A table has one home, and dead code goes in the commit that stops using it.** A second
   literal table with the same members is a bug. *Evidence:* sentence ends are defined in
   several places, number words in three, and `IrregularVerbForms.swift` is unused but tested.
5. **Show the measured value, and treat missing evidence as its own value.** Never default an
   unknown to the strongest value, and never render a sentinel. *Evidence:* an override is
   written with confidence 1.0 (`DictationPipeline.swift`), and the prompt prints "heard at
   0.00" for words scored 0.97 (`PromptBuilder.swift`).
6. **A configured threshold needs a live signal behind it, proved by a test that varies the
   signal.** *Evidence:* `noSpeechThreshold` is set to 0.6 while WhisperKit 1.1.0 returns a
   constant 0 for the probability it is compared with (`TextDecoder.swift`).
7. **Read the artefact before you write the premise.** Before an issue says "X does not exist",
   search the module's own vocabulary; before it proposes reusing a computed value, say what
   the value depends on; before it says a library cannot do something, cite the access level
   of the symbol. *Evidence:* a prompt-prefix cache proposed for reuse across audio depends on
   the audio; a field observer reported missing exists in `CommitDetector.swift`.
8. **A claim about speed or accuracy, in a document or in the interface, names the measurement
   that makes it true and where its clock starts and stops.** State a threshold by naming the
   constant, not by repeating its value. *Evidence:* a "length-independent wait" taken from a
   harness that ends at "words ready" and inserts breaths into its audio.
9. **A fix for behaviour that depends on its neighbours is proved by a property over every cut
   of the corpus, not by the failing example.** A pass that reads its neighbours runs once over
   the joined message. *Evidence:* `PieceJoiner.swift` has had 19 fix commits since the piece
   design settled and two example tests of the invariant behind them.
10. **A pull request that changes cleaning code may add corpus cases but does not edit an
    existing case's expectation without naming the issue that decided it.** The instrument
    must not move with the patch. A decision to decline an approach is written, with its
    evidence, in `Docs/`.

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
