# The disclosure gate

The gate enforces [Docs/agents/public-boundary.md](agents/public-boundary.md). `Scripts/disclosure_audit.py` is the single implementation;
every layer below runs it.

| Where | What it sees |
|---|---|
| `make verify` | the working tree, before the build, beside the PII audit |
| `.githooks/pre-push` | every commit being pushed, to any branch |
| `.githooks/commit-msg` | the message, before it is recorded |
| `.github/workflows/quality.yml` | the pull request's whole range, plus its title and body |
| `.claude/settings.json` | the text of a command a Claude Code agent is about to run |

There are five layers because no single one holds: the hooks run only where `make hooks` was run,
the settings hook binds only Claude Code, and the workflow sees only what is pushed. The ways
around each do not overlap.

## Two kinds of pattern

- **Names and phrases** fail outright.
- **Vocabulary that is usually innocent and occasionally the tell** is counted against
  `Scripts/disclosure_baseline.json`. A count may fall and never rise.

In text being written now — a message, a pull-request body, an added line — both kinds fail,
because new writing has no legacy to grandfather. The terms are stored base64 so the gate does
not publish what it exists to keep out and does not match itself on every run.

```bash
python3 Scripts/disclosure_audit.py --show-terms          # the lists, decoded
python3 Scripts/disclosure_audit.py --history             # every commit on every ref
python3 Scripts/disclosure_audit.py --update-baseline     # record a fall
```

A document that states the rule can legitimately need a counted word. `--update-baseline
--absorb` records that rise and prints it, so it appears in the baseline's diff for a reviewer.
Use it when the word is the subject, never to make a paragraph fit.

The one path exemption is the evaluation corpus, from the phrase patterns only; it does not cover
names.
