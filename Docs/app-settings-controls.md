# Settings controls

`SettingsControlView` in `Sources/Uttrflow/Settings/SettingsControlView.swift` draws whatever a
settings row asked for (`SettingsControl` in `Sources/UttrflowUX/SettingsPresentation.swift`). It
is one `switch` over a closed set, so a control the presenter can ask for and the page cannot draw
does not compile. Every case reports the change the presenter already attached to the choice; none
of them works out what a choice ought to mean. `SettingsViewModel` carries the page's state and the
shortcut recording. Why the choices are shaped as they are is in
[`ux-settings-model.md`](ux-settings-model.md); the shortcut rules themselves are in
[`core-hotkeys.md`](core-hotkeys.md).

## Labels and VoiceOver

Every control here is drawn with `labelsHidden()`, because the row already writes the label beside
it. The label is still passed in and reattached with `accessibilityLabel`; with an empty label
SwiftUI has nothing to hand to VoiceOver, and a switch would be announced as "checkbox, checked"
naming nothing. The row's own words are the right label.

A language chip's × says which language it stops listening for, since a bare × names nothing, and
the last language has no × at all rather than one that is refused after it is pressed.

## Destructive versus ordinary buttons

`.removal` routes through `model.request`, which asks for confirmation where the level needs it,
and is red when it resets everything. `.action` is neither red nor confirmed. The two cases exist
precisely to keep those treatments attached to one of them and not the other, and neither is ever
`.keyboardShortcut(.defaultAction)`: nothing on this screen removes anything because Return was
pressed.

## Recording a shortcut

Keystrokes are taken through a local `NSEvent` monitor (`addLocalMonitorForEvents` for `.keyDown`
and `.flagsChanged`) rather than SwiftUI's focus machinery, because the combinations worth
recording, ⌘Q and ⌥Space, are the ones the menus and the responder chain would otherwise eat before
any view saw them. The monitor is installed only while recording, and starting to record announces
the field to VoiceOver.

### `.flagsChanged` as well as `.keyDown`

A modifier pressed on its own sends only `.flagsChanged`. Without listening for it, somebody trying
to bind ⌘ or Fn alone would press their key and the field would say nothing at all: no shortcut, no
refusal, just "Press the new shortcut" for ever. Silence reads as a broken field rather than as a
rule. A binding that is genuinely undeliverable is still refused; the point is that it is refused
out loud.

A modifier-only press (⌃⌥, or ⌘ on its own) arrives with the flags set and a modifier's own key
code, and is recorded as the hold it is (`isDown(keyCode:phase:modifiers:isFunctionDown:)`), rather
than falling through to the refusal meant for an ordinary key.

`.flagsChanged` also fires on the release, where the flags have gone empty. Only the press is an
attempt at a shortcut; reporting the release as one would answer a single tap with two different
complaints.

### Fn

Fn is a shortcut in its own right (held, not combined), so it is recorded rather than refused. It
carries none of the four modifiers this app names, so it is recognised by `.function` and its own
key code (`HotkeyBinding.functionKeyCode`) before the empty-modifier check would throw the press
away as a release.

### What is swallowed and what is passed on

`route(_:)` decides. A key press is swallowed (`.recordAndConsume`), so nothing pressed at this
field reaches the rest of the app: recording ⌘Q records or refuses that candidate, but it does not
quit Uttrflow. A modifier change is passed on (`.recordAndPass`): swallowing one would leave the
rest of the app believing a key is still held after the user let go.

Only four modifiers are recognised: command, option, control, shift (`modifiers(from:)`). Caps
Lock, Fn and the numeric-keypad bit are noise the window server sets on its own.

### The field owns the recording only while it is the key interaction surface

The main window losing the keyboard cancels the recording, through
`MainWindowController.onSettingsLostFocus` and `SettingsViewModel.shortcutRecordingSurfaceDidLoseFocus()`,
because a keystroke meant for the next application must not be saved as Uttrflow's shortcut.
Cancelling removes the monitor and restores the live shortcut monitor. Leaving the Settings page
for another page does the same, and so does a search that hides the row that is listening.
