# Phase 0 — what tab-to-complete can rely on

Measurements taken before any of the feature was built, so the design rests on numbers
from this machine rather than on estimates. Re-run everything here with
`uttrflow-dev probe`.

The surface sweep here is the widest single reading of other applications in the repository, and
it feeds the `Published`, `Caret` and `Value` columns of
[compatibility.md](compatibility.md).

Apple M5 Pro, release build, SQLite 3.53.2. Every timing is a median of 100 runs after
20 warm-up runs. The retrieval rows, and a re-take under load, are in
[probe-log.md](probe-log.md#rows).

## Retrieval — settled

`uttrflow-dev probe retrieval`, 50,000 synthetic entries of commands, URLs and phrases.

| Query | Median |
|---|--:|
| SQLite range scan, `text >= 'git c' AND text < 'git d'` | **4.7 µs** |
| Same rows through `LIKE 'git c%'` | 19.8 µs |
| Fuzzy scan, no prefilter | 7,128 µs |
| Fuzzy scan, 6-byte character mask | **478 µs** |
| Fuzzy scan, 12-byte character mask | 1,764 µs |

Three things follow, and the third was not expected.

**Write the range scan, not `LIKE`.** Four times slower here for a bare `LIMIT 8`. An
earlier measurement of the same comparison *with* `ORDER BY count DESC` put the penalty
near seventeen times, because the sort has to see every match before it can rank them.

Phase 2 found out *why* the gap varies, by asking SQLite rather than timing it:

```
RANGE: SEARCH entry USING INDEX entry_prefix (surface_id=? AND text>? AND text<?)
LIKE : SEARCH entry USING INDEX entry_prefix (surface_id=?)
```

`LIKE` is not a full table scan — it is a full *surface* scan. Both use the index, but
only the range constrains the text column, so `LIKE` reads every row belonging to that
field and filters them one by one. The penalty therefore grows with how much one field
holds, which is why a small corpus shows four times and a ranked query over a large one
shows far more.

This is asserted in the test suite as a query plan rather than a timing. A wall-clock
threshold measures whichever machine CI happens to run on — a 200 µs bound calibrated
here failed at 495 µs on a shared runner — while the plan is the same everywhere and
fails precisely when somebody rewrites the query as a `LIKE`.

**Fuzzy stays a fallback, never a parallel path.** `git p` matches 925 entries exactly
and 2,776 within one edit — and the extra matches are other commands, `git commit` among
them. Running fuzzy beside exact would answer "did you mean `git commit`?" to somebody
typing `git push`. It runs only when the exact scan returns nothing with support behind
it.

**The character-mask prefilter's strength is its window width.** A mask over the first
*n+k* bytes of an entry, matched to the query, gives **14.9×**. A fixed 12-byte window
gives 4.0× — sound, because a wider window can only make the filter weaker and never
rejects a true match, but most of the gain is lost. Phase 2 must therefore hold masks at
a width the query can choose from rather than one width for everything.

Damerau, not Levenshtein: `gti c` is one edit from `git commit` only when transposition
costs one. Under plain Levenshtein it is two, and the query the user actually mistypes
would be missed.

## The placement ladder — implemented and tested

`SurfaceCapability.placement` decides where a suggestion can be drawn for one field:

| The field reports | Placement |
|---|---|
| Its text and its caret rectangle (styling optional) | Inline ghost |
| Its text only, with no caret rectangle | Nothing is drawn |
| Nothing, or it is a secure field | Nothing is drawn |

`CapabilitySweep` aggregates readings and answers the one question phase 0 exists to
settle: whether the inline ghost reaches enough fields to lead with. Below 30% it does
not — and since the inline ghost is the only surface, there is nothing to fall back on.

## The application sweep — measured

`uttrflow-dev probe surface --seconds 240`

Taken on macOS 26.5.1 (25F80), MacBook Pro, Apple M5 Pro, release build. 28 focused elements
across 21 applications, each brought to the front in turn with the caret put in one of its
fields — a search field, a quick-open field or a message composer, whichever the application
offers without creating a document.

The columns are the suggestion loop's own reading. Until this run they were not:
`SurfaceProbe.read` answered the three capability questions itself, with a caret test that
accepted the zero-size rectangle Chromium and Terminal return for an empty range, a style
test that looked for a font object no application sends, and a secure test narrower than
`SecureField`'s. It measured a reader nothing draws from — every field claimed no styling,
and fields with nowhere to put a caret claimed they had one. It now goes through
`FocusedFieldReader.snapshot`, so the table says what the feature will do.

| Application | Role | Field | Value | Caret | Style | Secure | Read | Placement |
|---|---|---|---|---|---|---|--:|---|
| Activity Monitor | AXOutline | Processes | no | no | no | no | 947 µs | nothing |
| Calendar | AXTextField | ToolBarSearchField | yes | yes | no | no | 1428 µs | inline ghost |
| ChatGPT | AXTextArea | Do anything | yes | yes | no | no | 1497 µs | inline ghost |
| Claude | AXTextArea | Prompt | yes | yes | no | no | 1494 µs | inline ghost |
| Cursor | AXTextArea |  | yes | yes | no | no | 1456 µs | inline ghost |
| Cursor | AXTextField | Search files... | yes | no | no | no | 1072 µs | nothing |
| Finder | AXOutline | ListView | no | no | no | no | 868 µs | nothing |
| Finder | AXTextField | PathTextField | yes | yes | yes | no | 1288 µs | inline ghost |
| GitKraken | AXWebArea |  | yes | yes | no | no | 4228 µs | inline ghost |
| Google Chrome | AXTextField | Find | yes | no | no | no | 2905 µs | nothing |
| Google Chrome | AXTextField | Press Tab then Enter to ask AI Mode | yes | no | no | no | 1576 µs | nothing |
| Mail | AXTextField | — | yes | yes | no | no | 73730 µs | inline ghost |
| Messages | AXGroup | — | no | no | no | no | 1123 µs | nothing |
| Messages | AXTextField | Search | yes | no | no | no | 3207 µs | nothing |
| Music | AXSheet | — | no | no | no | no | 828 µs | nothing |
| Notes | AXTextField | — | yes | yes | no | no | 1036 µs | inline ghost |
| Notes | AXWindow | _NS:6 | no | no | no | no | 687 µs | nothing |
| Reminders | AXWindow | _NS:10 | no | no | no | no | 703 µs | nothing |
| Safari | AXTextField | WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD | yes | yes | no | no | 2619 µs | inline ghost |
| Slack | AXRadioButton | Home | no | yes | no | no | 2602 µs | nothing |
| Stickies | AXTextArea | _NS:153 | yes | yes | yes | no | 1368 µs | inline ghost |
| System Settings | AXTextField | Search | yes | yes | no | no | 1968 µs | inline ghost |
| System Settings | AXWindow | — | no | no | no | no | 1147 µs | nothing |
| Terminal | AXTextArea | shell | yes | yes | no | no | 2720 µs | inline ghost |
| TextEdit | AXTextArea | First Text View | yes | yes | yes | no | 1340 µs | inline ghost |
| WhatsApp | AXStaticText | TokenizedSearchBar_TextView | no | yes | no | no | 4871 µs | nothing |
| WhatsApp | AXTextArea | ChatBar_ComposerTextView | no | yes | no | no | 2777 µs | nothing |
| Zed | AXWindow | — | no | no | no | no | 641 µs | nothing |

**46% take the inline ghost, so the ladder decision is settled: lead with it.** The threshold
was 30%, and it is cleared without needing the applications the sweep did not reach.

Four things qualify it.

**The denominator is every focused element, not every text field.** Ten of the 28 rows are an
`AXWindow`, an `AXOutline`, a group, a sheet, a static text or a radio button — what the
application answered with while no field of its own had focus. Of the 18 rows that are a role
a person types into, 13 take the inline ghost, which is 72%. Both numbers are worth keeping:
46% is the reach over whatever the user happens to be focused on, 72% the reach over fields.

**Chrome's own fields take nothing.** Its omnibox and its find bar both report their text,
and both answer `AXBoundsForRange` with a zero-size rectangle at the left edge of the screen
— they do not list the attribute at all. Asked directly, with a messaging timeout forty times
longer than the read path allows, the answer does not change, so this is not the timeout
giving up. Safari's address bar, asked the same question, gives a real rectangle. Since there
is no fallback surface, nothing can be drawn in Chrome's browser chrome, and neither the
text-marker range nor the one-pixel-textarea fallback helps: both are for a Chromium *page*,
and these two fields are native.

Page content inside Chrome was not focused in this sweep, so the live confirmation
`Docs/predict-reliability.md` records as pending stays pending. What the sweep does show is
that the web path is not dead: GitKraken's `AXWebArea` — Chromium, in an Electron shell —
answers with a caret rectangle and takes the inline ghost.

**Almost nothing answers for styling, and that is survivable.** Only the three AppKit fields
here — Finder's path field, Stickies and TextEdit — describe the font at the caret, and they
do it with an `AXFont` dictionary rather than a font object. Terminal does not publish
`AXAttributedStringForRange` at all. The ghost therefore defaults its face and size nearly
everywhere, which the ladder already allows.

One reading was slow enough to name: Mail's search field took **73.7 ms**, against a median
near 1.4 ms. The read path gives up after 50 ms, so a field that answers like that some of
the time will drop the odd turn rather than hold the loop.

Every application named in the table was reached, and the table is the list. Not installed
here: Word, VS Code, Numbers, Pages, Linear, Notion, Figma. Installed and still unswept:
Xcode and Preview, neither of which offers a field to focus without first opening a project
or a document.

The run confirms what this page said it would: the binary needs no grant of its own and no
password, because Accessibility is attributed to the responsible process, which is the
terminal. `AXIsProcessTrusted()` returned true for the release build and for an unsigned
scratch binary built to check the readings above.

The probe prints each new field as it sees it, so the run can be watched. It asks system-wide
first and the application second, in that order, because apps answer one or the other and not
reliably both — the same ordering `Docs/insertion.md` records for the dictation path. Fields
are told apart by application, role and whichever of identifier, placeholder or description
the field publishes, so Chrome's address bar and its find bar do not collapse into one row.

## The event tap — pending the operator

`uttrflow-dev probe tap --seconds 20`, and `--stall` to force the system to disable it.

**Not yet run**, for the same reason: somebody has to be at the Mac while it runs. Its
trust check is satisfied the same way, from the terminal that already holds the grant.
Whether that is enough for the tap itself is untested: `CGEvent.tapCreate` can refuse
after `AXIsProcessTrusted()` has returned true, and a keyboard tap may want Input
Monitoring, which is a grant of its own. The probe tells the two apart rather than
failing silently — "The tap could not be created even though Accessibility is granted"
is that case, and it is the first thing this sweep will settle. What it will answer:

- Tab is swallowed while the tap is armed, and other keys pass through untouched.
- `--stall` sleeps two seconds inside the callback, which is past the system's patience,
  so the tap is disabled and the recovery path runs. The summary counts both.

## Open, and not answered by this probe

**Detecting a composing input method.** Measured since, in `Docs/predict-ime.md`. The
marked-text range the field exposes is real and public — `AXTextInputMarkedRange` — but it
reaches only AppKit multi-line text views, so everywhere else the answer is a capability
guess from the selected input source. Partly solved, and the doc says what the rest costs.

**Single-undo grouping.** Whether `⌘Z` reverts an accepted completion as one step is a
property of each target application, not of the insertion. It needs the sweep to have
run first, so it is deferred to the same session.
