# The key events this app posts, and what the system does with them

`CGEventKeystrokeSender` presses ⌘V and `CGEventTypist` types characters and presses
Delete. Both post events into the same stream the user's own keyboard feeds. An event can
carry both a Unicode string and a physical key code, and the receiving application decides
which representation it uses.
`Docs/insertion.md` covers where the events are posted; this page covers what is in them.

There are no per-application results on this page and there should not be: a posted event carries
the same thing wherever it lands. It feeds the `Completion` column of
[compatibility.md](compatibility.md) and the undo note beside it.

## Every posted event is stamped as ours

The feature reads the keyboard from two places — the `CGEventTap` in `KeyInterceptor` and
the `NSEvent` monitor in `SuggestionCoordinator` — and both see this app's own synthetic
keys upstream of the target application. Untagged, accepting a completion by pressing Tab
would type a Tab that the tap then read as another accept.

`SyntheticEvent` writes a sentinel into `.eventSourceUserData` before the event is posted,
and both readers drop anything carrying it. The value is deliberately not zero: an event
that never had the field set reads as zero, so zero would make every ordinary keystroke
look like ours.

## Typed text uses one mapped key per character

`CGEventTypist` posts one key pair per Unicode scalar. Each event carries that scalar as
its Unicode string and uses the current layout's physical key code for the same character;
when the layout produces it with Shift, the event carries Shift as well. This lets a field
that reads the Unicode string receive the character and gives a field that reads physical
keys a matching key and modifier instead of key code 0. Text is resolved in full before
any event is posted. If a scalar has no single physical key on the selected layout, typing
refuses the whole string. Completion checks that condition before deleting the text it
would replace.

The event format alone does not establish which representation a particular application
uses. The `Completion` column in [compatibility.md](compatibility.md) records observed
results by application; it does not identify whether a successful field read the Unicode
string or the physical key. Terminal emulators, cross-platform editors, remote desktops,
virtual machines and games still need measurements that separate those two behaviors.

## Flags are cleared on every event

A modifier the user is still holding when the paste or the typing goes out is applied to
it: the shortcut is held down while dictation ends, so ⌥ on a typed `t` becomes `†`, and
a Delete with ⌥ held deletes a whole word instead of one character. Every posted event
sets `flags` explicitly rather than inheriting the current state — `.maskCommand` for the
⌘V, empty for everything else.

## One Delete per character

There is no bulk delete a synthetic keyboard can reach for, so taking back what a
completion replaces costs one key-down/key-up pair per character. That is also why the
target application's undo sees several edits on this route and one on the Accessibility
route; `Docs/predict-accept.md` has what ⌘Z costs on each.

## The key code for ⌘V is resolved, not fixed

A key code is a key's *position*, but an application matches a ⌘ shortcut against the
*character* the current layout gives that position. On US QWERTY those agree, so posting
key code 9 has always looked like posting V — but on Dvorak the same position types `k`,
so the same event fires ⌘K instead. `PasteKeyLayout` reads the selected layout's table
with `UCKeyTranslate`, ⌘ held so a layout with a separate ⌘ map (Dvorak – QWERTY ⌘) is read
from that map, and caches the key code that produces `v` under it, falling back to
the system's ASCII-capable layout when the selected one has no Latin letters, and to key
code 9 when neither layout can be read. The cache fills on `startObserving()` and follows
`kTISNotifySelectedKeyboardInputSourceChanged`, on the main queue, the way
`CompositionProbe` reads Text Input Sources. `LayoutKeyCode.code(for:in:)` is the pure
lookup and is tested against real layout tables (QWERTY, AZERTY, Dvorak, and a layout with
a separate ⌘ map) rather than asserted here.
