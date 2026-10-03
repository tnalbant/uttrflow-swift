# Launch at login

The **Open at login** setting (`Settings.opensAtLogin`, on by default) asks macOS to start
Uttrflow when the user logs in. `LaunchAtLogin` in `Sources/UttrflowSettings/LaunchAtLogin.swift`
reads and changes the login item; `LaunchAtLogin+System.swift` beside it wires it to
`SMAppService.mainApp`, the app's own login item, so there is no helper bundle to install or keep
in step. `AppDelegate.applyLaunchAtLogin()` applies the setting at launch and whenever settings
change, and `synchronizeLaunchAtLoginWithSystem()` adopts the system's state each time the app
becomes active.

## Why `LaunchAtLogin` re-reads instead of believing `SMAppService`

Neither half of `SMAppService`'s answer means what it looks like:

- `register()` throws when the caller already has what it wanted, registering twice over a
  database that says enabled.
- `register()` returns without complaint for a build macOS will never launch: one that is not a
  signed app bundle. Its `status` is `.notFound`.
- `register()` can succeed and leave the app at `.requiresApproval`: macOS does not start it
  until the user allows it under Login Items, and asking again cannot move that on.

So a thrown error is not evidence of failure and its absence is not evidence of success.
`enable()` and `disable()` make the change with `try?` and return a fresh read of the status, the
only answer that says what happens at the next login. `status` is read afresh on every access for
the same reason: the user can change it in System Settings while the app runs.
`applyLaunchAtLogin()` logs an error when the state read back differs from the one asked for.

## What each state means

| `SMAppService.Status` | `LaunchAtLoginStatus` | Settings row |
|---|---|---|
| `.enabled` | `.enabled` | on |
| `.notRegistered` | `.disabled` | off |
| `.requiresApproval` | `.requiresApproval` | disabled: "macOS is waiting for you to allow Uttrflow under Login Items in System Settings." |
| `.notFound` | `.unavailable` | disabled: "This copy of Uttrflow is not installed as an app, so macOS has no login item for it." |
| a case this build does not name | `.disabled` | off |

`SMAppService.Status` is an Objective-C enum, so a later macOS can return a case this build does
not name. It maps to `.disabled`: certainly not enabled, it leaves the switch usable, and the
re-read after the next attempt tells the truth. `.unavailable` is what a developer running from
the command line sees: an honest "cannot" rather than a switch that appears to work. The row reasons come from
`SettingsEditor.unavailability(of:given:in:)`.

## Testing

The three system calls are injected through `LaunchAtLogin.init(readStatus:register:unregister:)`,
so outcomes a test machine cannot be talked into (a user who refused the app under Login Items, a
build macOS will not launch) run without writing to the real login-item database.
`LaunchAtLoginTests` combines "what the database ends up as" and "whether the call throws"
independently, because `SMAppService` combines them in all four ways. `LaunchAtLogin+System.swift`
is excluded from the coverage gate in `Scripts/coverage_report.py` and kept short enough that
reading it is the review. A launch with `UTTRFLOW_TEST_CONTAINER` set, as UI tests do, saves
`opensAtLogin = false` first, so a test run registers nothing.

Related: [`settings-decoding.md`](settings-decoding.md).
