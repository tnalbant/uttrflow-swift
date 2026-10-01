# Driving the real app

`make verify` proves the logic. It cannot prove the app opens a window, because there is no
window in a `swift test` process. That gap is what this suite is for, and it is deliberately
small: everything a headless test can assert belongs in a headless test, where it runs in
milliseconds and never flakes.

## Where it lives, and why it is not a SwiftPM target

SwiftPM cannot express a UI-testing bundle — `bundle.ui-testing` is an Xcode product type. So
`UITests/project.yml` describes one target, `Scripts/uitest.sh` generates a project from it with
XcodeGen, and the generated `.xcodeproj` is gitignored. The configuration is the source; the
project is build output.

Nothing about the app's own build changes. SwiftPM still compiles it and `Scripts/bundle.sh`
still assembles it; the suite drives `dist/Uttrflow.app` through
`XCUIApplication(url:)` rather than building its own copy. That is the whole reason this can be
added without porting the project to Xcode.

```bash
brew install xcodegen   # once
make app                # the bundle under test
make uitest
```

`make uitest` always writes its result bundle to `dist/uitest.xcresult`, which is where
`xcodebuild` insists on writing fresh each run. Running it twice in a row does not fail on the
second attempt: `Scripts/uitest_result_path.sh` moves a bundle already there aside, under its own
timestamp, before `xcodebuild` runs, so the previous run's result stays on disk for debugging
instead of being deleted or blocking the next run.

## Why it is not in `make verify`

Three reasons, in order of how much they matter:

- **It needs a windowing session.** A UI test on a machine with no logged-in GUI session fails
  for a reason that has nothing to do with the change under test.
- **It needs permissions `make verify` never asks for.** Anything touching the keyboard tap, the
  microphone or a global hotkey needs Accessibility granted to both the app and the test runner.
  A GitHub-hosted runner cannot grant that, and cannot be made to.
- **It is slow enough to change how the gate feels.** `make verify` already takes 9–18 minutes on
  CI. The gate should not grow for tests that cannot run there anyway.

## The two tiers

**Launch and draw** — the tests here now. No permission, no state, no keyboard. That the app
comes up, that every settings pane renders, that quitting leaves nothing running. These can run
anywhere a screen exists, including a hosted runner.

**Keyboard and lifetime** — not written yet, and needs a machine with Accessibility pre-granted.
Posting `CGEvent`s to exercise a real shortcut is the automated form of the manual procedure
`shortcuts.md` already describes. A soak run — hours of synthetic activity, then a clean quit,
asserting object counts stayed flat — belongs here too, and is the only thing that can catch the
teardown crash class.

## What to be careful of

Each launch gets a unique disposable container through the test-only
`UTTRFLOW_TEST_CONTAINER` environment variable. App data, singleton locks and the settings and
onboarding defaults suite all use that container's identity. `AppUnderTest.terminate(_:)` waits
for exit and removes it, so a UI run neither reads nor writes the installed app's local state and
does not contend for the installed app's singleton locks. UI-test mode also uses an in-memory
account, suppresses automatic update checks, and makes login-item actions inert. This is the
isolation needed before the keyboard and lifetime tier can be repeated safely.

Selectors are titles the presenters produce. When a pane is renamed, this suite is where it is
felt, which is the cost of testing what the user sees rather than what the code returns.

## Screen capture privacy

The clipboard panel, the main window and the suggestion overlay set `NSWindow.sharingType` to
`.none`; `WindowSharingTests` covers that AppKit configuration. Before a release on a new macOS
minor version, check the actual capture tools below because not every capture path has honoured
that setting on every release.

| macOS | Screenshot | QuickTime recording | Video-call share | Notes |
|---|---|---|---|---|
| 14 | not checked | not checked | not checked | Record the app version and capture tool used. |
| 15 | not checked | not checked | not checked | Record the app version and capture tool used. |
| 26 | not checked | not checked | not checked | Record the app version and capture tool used. |

For each row, open the quick panel on copied text and a copied picture, open the History page
with a recent dictation visible, and show an inline suggestion in another app. The captured
output should omit those Uttrflow windows; if a tool still captures them, record that limit here
and keep ordinary secret masking as the fallback protection.
