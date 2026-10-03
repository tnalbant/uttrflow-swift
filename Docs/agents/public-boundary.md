# What must never reach a tracked file

This repository is public: strangers read it, search engines index it, and history keeps it
forever. The conversation that produces a change, with a person or an agent, is not public, and
the boundary is one way.

**A tracked file, a commit message, a pull-request title or body, an issue or a code comment
states technical requirements and technical decisions, in the product's own words, and nothing
else.**

## Rules

1. Reference material is for reading, not keeping. Take the requirement out of anything shared
   during the work (a link, a screenshot, a transcript, another product's behaviour), state it in
   product terms, and let the reference go, "temporarily" included.
2. Describe behaviour, never whose it is and never who said it.
3. Unsure whether something is a technical requirement? Leave it out.
4. Deleting a line from the tree leaves it in every commit that carried it. If something that
   should not be public is already committed, stop and tell a maintainer privately before
   changing anything.
5. Never weaken the gate or exempt a path to make a commit pass. A failing gate is the gate
   working.

## Checks

| Rule | Check | Pass |
|---|---|---|
| No conversation or reference material in the tree, messages or PR text | `python3 Scripts/disclosure_audit.py` | exits 0 |
| Counted vocabulary never rises | the same command, against `Scripts/disclosure_baseline.json` | no count above baseline |
| No personal data in fixtures | `make pii-audit` | exits 0 |
| No credentials, keys or private infrastructure identifiers | `Scripts/gitleaks_audit.sh` | exits 0 |
| Gate unweakened | `git diff origin/main -- Scripts/disclosure_audit.py Scripts/disclosure_baseline.json` | no loosened pattern, no new path exemption |

How the gate is layered and ratcheted: [`../disclosure-gate.md`](../disclosure-gate.md).
