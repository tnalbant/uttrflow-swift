# Graphflow in this repository

`graphflow.yaml` is the repository-specific input for Graphflow. The Graphflow engine
provides the runner; this file tells it how this repository is built, checked, and governed.
The config is intentionally specific to Uttrflow, while the engine remains repository
agnostic.

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
| `release` | Releases are tags on `main`, and the release owner handles tagging and releasing. |
| `issues.provider` | Uses GitHub for issue tracking. |
| `tracker.path` | Uses `PLAN.md` at the root of the checkout as the run's working tracker. The file is gitignored and local to each checkout; future work is a GitHub issue. |
| `rules_files` | Loads `AGENTS.md` and `Docs/shortcuts.md` as repository rules. |
| `build.components` | Defines focused checks for keyboard, settings, and dictation pipeline work. |
| `autonomy.hard_stops` | Stops for `schema` or `infra` changes. |
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
Changes to the config or this guide go through a pull request to `main` under the repository
rules. The release owner alone makes releases, as specified in the config and `AGENTS.md`.

`make docs-audit` checks that the guide named by `graphflow.yaml` exists, so removing or
renaming it requires updating the reference and its check together.
