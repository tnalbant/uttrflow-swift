# Graphflow in this repository

`graphflow.yaml`, at the repository root, is this repository's input for Graphflow, an
agent-workflow runner installed separately. The engine is repository agnostic; the file tells
it how this repository is built, checked and governed.

## Starting a run

This repository does not define or pin a Graphflow executable or command-line syntax. Start
Graphflow through the runner installed for your environment, with this repository as the
checkout. The runner reads `graphflow.yaml`; its launch command belongs to the Graphflow
installation, not this repository.

The configured repository-wide gate is `make verify`. To run that gate without Graphflow,
run `make verify` from the repository root. The config also lists focused test commands for
the keyboard, settings, and dictation pipeline components below.

## What the config directs

| Setting | Repository behavior |
| --- | --- |
| `gate.command` | Runs `make verify` as the repository-wide gate. |
| `vcs.integration_branch` | Uses `main` as the integration branch. |
| `vcs.release_branch` | Uses `main`; this repository has no separate release branch. |
| `release` | A release is a tag on `main`; a tag with anything after the version is a prerelease. A maintainer tags; agents never do. |
| `issues.provider` | Uses GitHub for issue tracking. |
| `tracker.path` | Names `PLAN.md`, an untracked working tracker at the root of a checkout; it is gitignored, and in a fresh clone the file does not exist. Future work is a GitHub issue. |
| `rules_files` | Loads `AGENTS.md` and `Docs/shortcuts.md` as repository rules. |
| `build.components` | Defines focused checks for keyboard, settings, and dictation pipeline work. |
| `autonomy.hard_stops` | Stops for `schema` changes (stored settings reach every install) and `infra` changes (publishing moves `latest.json`). |
| `run.max_concurrency` | Allows up to four concurrent runs. |

The focused component checks are:

| Component | Source path | Test command |
| --- | --- | --- |
| `keyboard` | `Sources/UttrflowInput` | `swift test --filter 'Hotkey|SystemKeyboard|Activation'` |
| `settings` | `Sources/UttrflowUX` | `swift test --filter 'Settings'` |
| `pipeline` | `Sources/UttrflowPipeline` | `swift test --filter 'Dictation'` |

## Ownership and changes

Repository maintainers own the Uttrflow-specific values in `graphflow.yaml`. Keep those
values consistent with `AGENTS.md` and the source tree. In particular, branches
and review rules come from `AGENTS.md`; Graphflow settings do not override that policy.
Changes to the config or this guide go through a pull request to `main`. Only a maintainer
tags and releases, as the config and `AGENTS.md` both say.

`make docs-audit` checks that the guide named by `graphflow.yaml` exists, so removing or
renaming it requires updating the reference and its check together.

Related: `AGENTS.md` holds the branching and review rules the config defers to; [releasing.md](releasing.md) covers what a release is.
