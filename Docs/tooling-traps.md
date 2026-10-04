# Tooling traps

Each of these costs time the first time and is cheap once known.

- **`swift-format` is not on `PATH`.** Run `xcrun swift-format`, via `make lint` and
  `make format`. Capture its exit code explicitly: reading the output through a pipe swallows
  the failure. zsh has `$pipestatus` (lowercase, 1-indexed), not `$PIPESTATUS`.
- **zsh does not word-split unquoted variables.** `kill -9 $PIDS` passes one newline-joined
  blob and fails with "illegal pid". Pipe to `xargs -n1`, or use `${=PIDS}`.
- **`DEVELOPER_DIR` is not inherited.** A git hook does not read an interactive shell
  profile; export `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before any swift
  command.
- **MLX targets cannot be built by `swift build`.** They need `xcodebuild` plus the Metal
  Toolchain (about 690 MB). MLX is quarantined in `UttrflowLocalModel` and `uttrflow-bakeoff`
  so nothing else needs it.
- **The app is built with `xcodebuild`, not `swift build`.** SwiftPM bakes an absolute path
  into the generated resource-bundle accessor and puts the bundles where a signed app cannot
  carry them. `Docs/packaging.md` has the measurements.
- **`git ls-files` and `git grep` see only tracked files.** A repository-wide rename or check
  that uses them skips new files and reports "clean". Use `find`, `git grep --untracked`, or
  `git ls-files --cached --others --exclude-standard`.
- **`secrets` is not available in a workflow step's `if:`.** The condition evaluates to nothing
  and every guarded step runs.
- **Quote every glob in zsh.** `grep --include='*.swift'` unquoted aborts the whole command with
  "no matches found" when nothing matches, and the failure reads like an empty result. Quote the
  pattern, and quote paths that contain spaces.
- **A shared `.build` corrupts under two concurrent builds.** Run one build per checkout or
  worktree at a time.
