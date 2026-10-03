# Working in this repository

`AGENTS.md` is the one rulebook for every agent — Claude, Codex, Cursor, Copilot or any
other — and for every human contributor. `CLAUDE.md`, `.cursor/rules/` and
`.github/copilot-instructions.md` only point here; new rules go in this file, never in theirs.

Most rules below exist because the obvious path was tried, cost something and was abandoned,
so an agent reasoning from first principles will propose things already rejected here. A rule
that names a command is enforced by that command failing; a rule with no command is a
judgement, and the pull request is where it is checked.

## Read order

1. This file.
2. `AGENTS.local.md`, if it exists — see the next section.
3. `PLAN.md`, the live phase tracker. Read it rather than reconstructing the state of the
   project from `git log`.
4. The `Docs/` page for the module you are about to change.

## Local rules — untracked, private to one person

This file is tracked and public, so nothing goes in it that you would not hand to a stranger.
A rule that is one person's own — private context, preference, reasoning, anything not fit
for a stranger to read — goes in **`AGENTS.local.md`**, which is gitignored and never committed.

- **Where.** The root of the main checkout. A worktree does not carry untracked files, so from
  `.claude/worktrees/<name>` read it with
  `cat "$(git rev-parse --git-common-dir)/../AGENTS.local.md"`.
- **Anyone may create one.** Each is private to its owner. A missing file is normal: carry on
  with this file alone.
- **It adds and tightens; it never loosens.** Where the two disagree, this file wins and the
  disagreement is reported.
- **It does not leak back.** Nothing in it is quoted, summarised or paraphrased into a tracked
  file, a commit message, a pull request, an issue or a comment.
- **Where does a new rule go?** Here if a stranger could read it and every contributor needs
  it. In the local file otherwise. When unsure, local.

<!-- release-policy:v4 -->
## Branching & release policy — NON-NEGOTIABLE

There is no `beta` branch, and agents do not merge their own pull requests.

**One long-lived branch, `main`, always releasable. A release is a tag, not a branch.**

```
branch / fork  ──PR──>  main  ──tag v26.0926.0-rc.1──>  prerelease  (soak)
   (CI runs)          (CI runs)  ──tag v26.0926.0────>  release
```

1. **Cut every branch from `origin/main`**, freshly fetched. Short-lived: a branch that lives
   for weeks is a merge conflict being written slowly.
2. **Every PR targets `main`** — `gh pr create --base main`.
3. **CI runs on every pull request and must be green.** `.github/workflows/ci.yml` runs
   `make verify` and builds the app bundle; dependency review and the text checks run
   beside it. CodeQL is weekly, not per-PR, and gates nothing. Run `make verify` locally
   first — it is the same command.
4. **Nobody pushes to `main` directly.** A ruleset blocks force-pushes and deletions, and
   everything reaches `main` through a pull request. Never force-push `main`, and never tag:
   tagging is the release, and the release is the operator's.
5. **An agent stops at a green pull request.** The live `main` ruleset requires one approving review.
   It also requires code-owner review, resolution of review threads, dismissal of stale
   reviews after a push, and approval by someone other than the last pusher. The branch
   must be up to date with `main`, enforced by `strict_required_status_checks_policy`, so
   what merges is what was tested.
6. **Green means green, not nearly.** A check still running is not a passed check. Merging
   past a failing or unfinished check happens only on the operator's instruction, and the
   report says so plainly — never silently with `--admin`.
7. **Your task is done when the pull request is open, green and documented for review, and
   the session has ended clean** (next section). Do not tag, and do not release.

**There is no staging branch.** The gate belongs on the pull request: CI tests the merge result
*before* it lands, where a staging branch tests code already merged into a shared branch. What
a staging branch additionally gave — a build people run before it is the default — is what
`-rc` tags give. Do not propose reinstating one.

Releases are batched and infrequent. `main` accumulates merged work and the operator decides
when a commit on it becomes a release. See `RELEASING.md` and `Docs/releasing.md`.

## Every session ends clean — NON-NEGOTIABLE

**A session that starts work finishes it: it leaves no worktree, no local branch, no build
output and no running process behind.** Each worktree carries its own `.build` (0.5–5 GB), and
185 abandoned ones once held 89 GB. An abandoned worktree is indistinguishable from work in
progress, so only the session that made it can safely remove it.

1. **Worktrees live in `.claude/worktrees/<name>` and nowhere else** — not beside the repo,
   not in a scratchpad or `/tmp`. One place is what makes leftovers findable.
2. **Never end with work only on this disk.** Commit and push it to `origin/<name>` — a
   draft pull request is fine — or, if it is abandoned, say so and discard it.
3. **Once the branch is pushed, remove the worktree and the local branch** — as soon as the
   pull request is open, not when it merges. `origin/<name>` is what keeps it reachable.
4. **Stop what you started** — dev servers, background `make` runs, simulators, monitors,
   scheduled loops — and delete scratch output outside the worktree.
5. **Close the thread.** In the Claude desktop app, archive the session; elsewhere, end the
   conversation. An open idle thread holds its worktree and its slot.
6. **Check before you say done.** `git worktree list` shows nothing of yours, and
   `git branch --list <name>` prints nothing.

**Never remove a worktree you did not create** unless it is clean, every commit on it is on
`origin`, and no process is working in it (`lsof -a -d cwd | grep <path>`). If any of the
three fails, it is somebody's work: leave it and report it.

**Every feature is built in a worktree cut from `origin/main`, then merged into `main` by PR.**

```bash
git fetch origin
git worktree add .claude/worktrees/<name> -b <name> origin/main   # from main, not from HEAD
cd .claude/worktrees/<name>                                       # and stay there
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
… work, commit by name, `make verify` before every push …
git push -u origin <name>
gh pr create --base main --head <name>
cd "$(git rev-parse --git-common-dir)/.."                        # back to the main checkout
git worktree remove .claude/worktrees/<name>                      # refuses if anything is unsaved
git branch -d <name> 2>/dev/null || git branch -D <name>          # safe: the commits are on origin
# no `git push origin --delete` — the remote branch stays, always
```

**Remote branches are never deleted, merged or not.** `origin/<name>` is the pull request's
source ref. When CI or review asks for a change after cleanup, re-fetch it rather than opening
a new branch or pull request:

```bash
git fetch origin
git worktree add .claude/worktrees/<name> origin/<name>
```

More than one agent works here at once, and a shared `.build` corrupts under two concurrent
builds.

**Never run `swift build` or `swift test` in the main checkout while subagents are
working.** Give parallel agents `isolation: "worktree"`, or cut the worktrees by hand with the
recipe above and point each agent at one by absolute path.

**`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`** before any swift
command, in every shell and in every agent prompt. A hook or subagent does not inherit it.

## Stop and ask

Stop, report what you saw, and wait — never force-fix, never delete state to make a command
succeed — when you meet any of these:

- a commit on `main`, or a branch, worktree or pull request you did not create;
- a merge, rebase or cleanup you cannot complete cleanly;
- a secret, personal data or session-only material already committed or published;
- a gate that fails for a reason you cannot explain;
- a change that would need a new workflow, a new dependency or a change to a promise in
  `Docs/definition-of-done.md`.

## Rules and the command that enforces each

| Rule | Enforced by |
|---|---|
| Comments are one line, present tense | `Scripts/comment_audit.py` (`make comment-audit`) |
| Nothing session-only reaches a tracked file | `Scripts/disclosure_audit.py` (`make disclosure-audit`) |
| No real email or postal address in a fixture | `Scripts/pii_audit.sh` (`make pii-audit`) |
| No spelling match decided by shape | `Scripts/loose_match_audit.py` (`make match-audit`) |
| 95% line coverage per module | `Scripts/coverage.sh` (`make coverage`) |
| The dictation path cannot reach the network | `Scripts/offline_audit.sh` (`make offline-audit`) |
| Docs describe this tree; `CLAUDE.md` imports this file | `make docs-audit` |
| The evaluation corpus is not in a shipped app | `Scripts/bundle.sh` |
| Everything above, plus build and tests | `make verify`, then CI on the pull request |

The rest of this file is the judgement the commands cannot make.

## What must never reach a tracked file — NON-NEGOTIABLE

This repository is public. Strangers read it, search engines index it, and git history keeps it
forever. The working session that produces a change is not public, and the boundary is one way.

**Tracked files, commit messages, pull-request titles and bodies, issues and code comments state
technical requirements and technical decisions, in the product's own words — and nothing
else.** What else stays out, with the reasons and the incidents behind it, is in
`AGENTS.local.md`.

1. **Reference material is for reading, not keeping.** Take the requirement out of anything
   shared in a session — a link, a screenshot, a transcript, a comparison — state it in the
   product's own terms, and let the reference go. This holds "temporarily" too.
2. **Describe behaviour, not whose it is** and not who said it.
3. **Unsure whether something is a technical requirement? Leave it out**, or put it in the
   local file.
4. **History counts.** Deleting a line from the tree leaves it in every commit that carried it,
   and a public repository has already published them. If you find something that should not be
   there, stop and tell the operator before touching anything; whether to rewrite history is
   theirs to decide.
5. **The rule lives here, tracked,** so a fresh clone, a worktree, a fork and CI all see it. The
   detail lives in the local file.

### How it is enforced

Five layers, because no single one holds. The hooks are skipped by `--no-verify`, the
workflow by an admin merge, and the settings hook binds only agents on this machine — but the
ways around each of them do not overlap.

| Where | What it sees |
|---|---|
| `make verify` | the working tree, before the build, beside the PII audit |
| `.githooks/pre-push` | every commit being pushed, to **any** branch |
| `.githooks/commit-msg` | the message, before it is even recorded |
| `.github/workflows/quality.yml` | the pull request's whole range, plus its title and body |
| `.claude/settings.json` | the text of a command an agent is about to run |

All five run `Scripts/disclosure_audit.py`. It reads two kinds of pattern: names and phrases,
which fail outright, and vocabulary that is usually innocent and occasionally the tell, which
is counted against `Scripts/disclosure_baseline.json` and may fall but never rise. In text
being written now — a message, a PR body, an added line — both kinds fail, because new
writing has no legacy to grandfather.

The terms are stored base64 so the gate does not publish what it exists to keep out and does
not match itself on every run. That is not obfuscation.

```bash
python3 Scripts/disclosure_audit.py --show-terms     # see the lists decoded
python3 Scripts/disclosure_audit.py --history        # every commit on every ref
make hooks                                           # install both git hooks
```

A document that states the rule can legitimately need a counted word. `--update-baseline
--absorb` records that rise and prints it, so it appears in the baseline's diff for a
reviewer. Reach for it when the word is the subject, never to make a paragraph fit.

**Never weaken this gate to make a commit pass**, and never add a path exemption. The one
exemption is the evaluation corpus, from the phrase patterns only; it does not cover names.
A failing gate is the gate working. `--history` is what a repository is judged on before it
is made public: a tree can be cleaned in one commit, and history cannot.

## Where this sits

Four pieces: this app; `uttrflow-backend` (the server, and the only thing that touches its
database); `uttrflow-fe` (the site); and `uttrflow-panel` (design source).

**Two databases, and they hold different things.** The server's holds an account: who somebody
is, what they have paid for, which machines are signed in. This app's local store — under
Application Support — holds the clipboard, the dictation history, the personal dictionary and
the snippets, and **none of it is ever sent anywhere**. Transcription is local, full stop: the
product's claim is that dictation happens on this Mac and stays here. Changing that is a
product decision with a privacy page attached, not a refactor.

Network access is not limited to the account backend: sign-in and session calls live in
`UttrflowAccount`, speech-model and tokenizer assets can be downloaded, and Sparkle checks for
and downloads app updates. The audit and its limits are in [`Docs/offline.md`](Docs/offline.md).
Opt-in crash diagnostics send scrubbed crash and hang reports to Sentry from
`UttrflowDiagnostics`; what is sent and why is in
[`Docs/crash-reporting.md`](Docs/crash-reporting.md).

## What dictation is for — NON-NEGOTIABLE

**The goal is an accurate transcript of what the speaker said, cleaned of the noise of speaking
and laid out the way they would have typed it. It is not a rewrite.**

The tidier is a filter. It removes what was never meant as words — "um", "hmm", "aah",
stammers, false starts, the discarded half of a spoken self-correction — and adds what speech
leaves implicit: punctuation, question marks where a question was asked, capitalisation,
numerals, line and paragraph breaks, a list when the speaker plainly spoke one. Every word the
speaker meant survives, in their order and their register.

It never shortens, summarises, changes tone, swaps synonyms, reorders, answers, obeys, or
finishes a thought. Those are rewrites; a user who wants one asks for it, and it is a different
feature. `Docs/cleanup.md` is the catalogue — three tiers: what is done, what is not yet, what
is forbidden. Every change to the prompt or the rules is measured against the corpus before
it lands (`make bakeoff`). "Make the output more polished" proposes a rewrite; the answer is no.

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

**Find why the defect exists and fix that. A patch, a workaround or a special case is never the
answer here, however small the bug looks.**

1. **Root cause first.** Before changing code, say why the bug exists and why it was not
   caught. A fix that makes one symptom go away and leaves the cause in place is rejected.
2. **No special cases.** Nothing keyed to one phrase, one app, one fixture or one reported
   sentence. If a rule cannot be stated for the whole class of input, the design is wrong.
3. **Refactor what you meet.** Code that is the wrong shape for the change is reshaped into a
   clean seam first: SOLID, DRY, and no abstraction that nothing needs yet (YAGNI). A
   ground-up rewrite is acceptable when the evidence says the design cannot carry the change;
   lowering the quality of the code is not acceptable under any deadline.
4. **Measure before it lands.** A change to recognition, correction or cleanup is judged
   against the corpus (`make bakeoff`) and records the before and after.
5. **Extendable by default.** Ask what the next case of the same kind needs, and make that a
   data or configuration change rather than another branch in the code.

The pull request states the root cause and why it cannot recur; a description that only says
what changed is incomplete.

## Comments: one line, present tense — NON-NEGOTIABLE

**A comment is one line. A doc comment is one line. Both say what the code does now.**

```swift
/// Refuses audio with no speech in it, so silence is not transcribed as words.
```

Not a multi-line account of what the function used to do, what was tried, and how often it
went wrong. What a function *does* is checkable against the code in front of you; what it
*used to do* is not checkable at all.

1. **One line per comment block.** No `///` or `//` run longer than one line.
2. **Present tense, about the present code.** What this function does, what this line is for,
   what the value means. Not what it did before, not what somebody tried.
3. **A reason is allowed when it changes what a reader would do** — "kept under the lock
   because `deinit` can run on any thread" earns its place. A reason that is only a story does
   not.
4. **A trailing comment on a line of code is exempt from the length rule** and still bound by
   the rest.
5. **Document a parameter only where one line covers it.** `swift-format` rejects a singular
   `- Parameter` on a function with more than one, and a plural `- Parameters:` block is
   multi-line by construction — so document all of them or none, and none is what this rule
   chooses. Say what is surprising about an argument in the summary line instead.

**Where the rest goes.** A measured number, a platform trap, an approach that was tried and
does not work belongs in `Docs/`, under a heading, where it can be read on purpose and revised
as a piece (`Docs/silence.md` and `Docs/stuck-recording.md` show the shape). Link to it in the
one line:

```swift
/// Judges the audio before it is decoded. See `Docs/silence.md`.
```

Deleting a hard-won measurement is not the point of this rule; moving it somewhere it stays
true is.

**Enforcement.** `Scripts/comment_audit.py` counts multi-line comment blocks per file against
`Scripts/comment_baseline.json` and fails when any file gains one. The baseline only goes down:
`--update` refuses to record a higher count, and shrinking one file does not pay for growing
another. Bring a file you are already editing down to the rule and re-record; do not rewrite
the repository in one pass.

```bash
python3 Scripts/comment_audit.py --report                 # what is left, worst first
python3 Scripts/comment_audit.py --update                 # re-record after improving a file
python3 Scripts/comment_audit.py --update --after-merge   # only when main moved under you
```

`--after-merge` is the one way a count may rise: rebasing onto `main` brings in files this rule
has not reached yet, and blocking a branch on those would punish the wrong person. It prints
every rise and records it where a reviewer sees the diff. Never use it to excuse your own
comments.

## Never decide that two spellings are the same word by their shape — NON-NEGOTIABLE

Not a prefix of *n* characters, not "one is a substring of the other". Ask:

- `MeaningPreservationGuard.sameForm` — whether two spellings are one word;
- `spelledInto` or `isWritten` — whether a word is written out at its own boundaries;
- `WordErrorRate.measure` — whether a word is still there *in the order it was said*.

Each is the single home for its question; a local reimplementation is how this goes wrong. A
shape match fails in one direction — it says "same" too easily — on paths whose failure is
*acceptance*, and an acceptance leaves no trace: a three-character stem let "confirm" become
"confuse" and "Aarav" become "Aaron" past the guard whose job is to refuse that.

`Scripts/loose_match_audit.py` counts these per file against `Scripts/loose_match_baseline.json`
and ratchets like the comment and disclosure baselines: a count may fall, never rise.

```bash
make match-report                                            # what is left, with the line
python3 Scripts/loose_match_audit.py --update                # re-record after tightening one
python3 Scripts/loose_match_audit.py --update --after-merge  # only when main moved under you
```

One match is baselined, and it is the shape with a legitimate answer: `CaretEchoPass` asks
which completion targets begin with what the user has typed, where a prefix is the question
rather than a stand-in for one. The audit reports the shape; you say why a given one is right.

## Everything else that is not a preference

**Fixtures hold no real personal data.** Never a real email address or postal address; use
`example.com` and an invented street. `Scripts/pii_audit.sh` fails the build on anything else
and runs first in `make verify`. This is a rule because the most available realistic value is
the one you can see from where you are sitting, and a published address cannot be taken back.

**Never do a `good first issue` yourself, and never take an issue somebody has claimed.** Those
labels are inventory for somebody else, not a task queue. Before opening a branch for any
issue, read its thread: if anyone outside has asked for it or said they are on it, it is
theirs — add the `claimed` label, reply, and find other work. If it carries `good first
issue` and nobody has claimed it, still leave it alone. `CONTRIBUTING.md` sets out what a
claim guarantees, and that promise is this side's to keep. If a branch is already open against
one, take the label off rather than leaving free work advertised that is about to be closed.

**Workflows are `.github/workflows/`, and adding one needs explicit approval.** Today: CI
(build and test), CodeQL (weekly static analysis), dependency review (new vulnerabilities and
licences), Oracle sweep (exhaustive randomized clipboard-reader tests, nightly and on related
pull requests), Quality (disclosure, workflow, spelling and link checks), Release (build and
publish), Scorecard (supply-chain posture) and Security (secret, workflow and dependency
scans). The project builds against macOS 26 frameworks and drives the real Accessibility,
clipboard and speech APIs, so it runs on macOS runners only. `make hooks` installs the local
gate, which is the fastest answer.

**Git hygiene.**

- **Never `git add -A`, `git add .` or `git commit -a`.** Another session's half-finished work
  gets swept into your commit under your message. Stage the paths you touched, by name.
- **Never rewrite pushed history, and never rebase while another session is committing.**
  Check first: `ps aux | grep -c '[c]laude.*--add-dir'`.
- **Rebase onto `origin/main` before opening the pull request.** `main` moves while you work,
  and rebasing keeps the diff the change you made. Rebasing an unpushed branch is not
  rewriting pushed history.
- **Nothing an agent does touches `main` except through a pull request** — not a push, not a
  rebase onto it, not a tag, not a docs commit that seems too small to matter. If you find
  yourself with a commit on `main`, stop and say so rather than tidying it away.
- **Commit messages carry no `Co-Authored-By` trailer.** The message says what the change
  does; who typed it is what `git log` records.

**Merging is not reviewing.** Nobody else read the change, so the pull request is where you
write down what you would have wanted a reviewer to know: the root cause, what was measured,
what was assumed, and what you are least sure of.

## Building and releasing

```bash
make verify        # lint, build, 8,000+ tests, coverage floor — what the gate runs
make hooks         # once per clone; hooks are not cloned
make app-hardened  # a build fit to test on another Mac
make dmg           # the disk image
make publish       # to the public downloads repository: this Mac's gh login by hand, RELEASES_TOKEN in the workflow
```

Agents build and verify; the operator releases. For reference:

- **Version** is `YY.MMDD.REVISION` (`26.0926.0`; tag `v26.0926.0`), hand-edited in
  `Resources/Uttrflow-Info.plist`; a second release that day is `26.0926.1`. Month before day,
  leading zero kept, so versions sort in date order. `CFBundleVersion` is what the updater
  compares, so it goes up by one every release. `YEAR.MONTH.DAY`, semver and the five-part
  `YEAR.MONTH.DAY.HOUR.PATCH` scheme are retired or rejected; `Docs/releasing.md` says why.
- **Downloads** go to the public **uttrflow/releases** repository, which holds disk images and
  `latest.json` but no source. The asset is `Uttrflow.dmg` with **no version in the name**,
  which is what keeps `/releases/latest/download/` permanent.
- **The tag names the release; notarisation has nothing to do with it.** A pushed tag publishes
  under exactly that tag (`release.yml` checks it against the plist), and a hand-run publish
  uses `v<version>` from the plist. `latest.json` records `gatekeeper`, and the site shows or
  hides the `xattr` instruction from that field.
- **A tag with anything after the version is a prerelease.** `v26.0926.0-rc.1` publishes as
  one, stays out of `/latest/`, and leaves `latest.json` and `appcast.xml` untouched, so
  neither the site nor the updater offers it. That is the soak; `v26.0926.0` releases it.

## Tooling traps, each of which cost real time

- **`swift-format` is not on `PATH`** — it is `xcrun swift-format`, via `make lint` /
  `make format`. Capture its exit code explicitly; reading the output through a pipe swallows
  the failure. zsh has `$pipestatus` (lowercase, 1-indexed), not `$PIPESTATUS`.
- **zsh does not word-split unquoted variables.** `kill -9 $PIDS` passes one newline-joined
  blob and fails with "illegal pid". Pipe to `xargs -n1`, or use `${=PIDS}`.
- **MLX targets cannot be built by `swift build`** — they need `xcodebuild` plus the Metal
  Toolchain (~690 MB). MLX is quarantined in `UttrflowLocalModel` and `uttrflow-bakeoff` so
  nothing else ever needs it.
- **The app is built with `xcodebuild`, not `swift build`.** SwiftPM bakes an absolute path
  into the generated resource-bundle accessor and puts the bundles where a signed app cannot
  carry them. `Docs/packaging.md` has the measurements.
- **`git ls-files` and `git grep` only see tracked files.** A repo-wide rename using them
  silently skipped four new files and reported "clean". Use `find`, `git grep --untracked` or
  `git ls-files --cached --others --exclude-standard` when the change must cover work in
  progress.
- **`secrets` is not available in a workflow step's `if:`** — the condition evaluates to
  nothing and every guarded step runs.

## The method that has repeatedly paid off

**Probe the real API before coding, and distrust an implausible number.** That is what caught
`AVAudioConverter` silently truncating 51% of audio, Apple's undocumented Hindi ability,
train-on-test contamination in the prompt examples, and the local models scoring 13% only
because nobody was stripping their `Cleaned: "…"` wrapper.

**A CLI is not a representative test bed for the Accessibility API**, and a well-behaved target
never exercises the broken path. `Docs/` and the comments in `Sources/UttrflowInput/` carry the
specific traps.

## Quality bar

- 95% line coverage per module, enforced by `Scripts/coverage.sh`. Exclusions live in
  `Scripts/coverage_report.py` **with a stated reason each, printed on every run** — an
  exclusion is never silent. An excluded file has to be small enough that reading it is a
  sufficient review: `make exclusion-audit` prints every exclusion's line count and fails over
  400 lines, unless the file is listed in `OVERSIZED_EXCLUSIONS` with what reviews it instead.
  Add tests until the exclusion can go; a shallow test that executes lines without asserting
  behaviour is worse than the exclusion it hides.
- Root cause, not patches: see "No patchy fixes" above.
- Swift 6 language mode, strict concurrency, warnings as errors.
- No force unwraps, no force try, no implicitly unwrapped optionals (lint-enforced).
- Nothing about the evaluation corpus may reach a shipped app; `Scripts/bundle.sh` checks the
  built artefact for it and refuses.

## Before you open the pull request

- [ ] Built in a worktree cut from freshly fetched `origin/main`, then rebased onto it.
- [ ] The description states the root cause, why it cannot recur, what was measured, what was
      assumed and what you are least sure of.
- [ ] A change to recognition, correction or cleanup records the corpus before and after.
- [ ] `make verify` is green locally; paths staged by name; no trailer in any commit message.
- [ ] Nothing in the diff, the commit messages or the description is session talk, or anything
      from `AGENTS.local.md`.
- [ ] After the push: worktree and local branch removed, processes stopped, thread archived.
