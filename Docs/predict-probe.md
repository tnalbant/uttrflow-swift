# Probes: what AI suggestions can rely on

`uttrflow-dev probe` measures, on the Mac it runs on, the three things AI suggestions
(tab-to-complete) depend on and cannot assume: how fast the corpus answers a prefix, what other
applications' fields publish through Accessibility, and whether the key tap holds. The commands are
in `Sources/uttrflow-dev/Probe.swift`, the retrieval benchmark in
`Sources/uttrflow-dev/RetrievalBenchmark.swift`, and the placement rule in
`Sources/UttrflowContext/SurfaceCapability.swift`. The surface sweep below is the widest single
reading of other applications in the repository and feeds the `Published`, `Caret` and `Value`
columns of [compatibility.md](compatibility.md). How the feature uses these answers is in
[predict.md](predict.md).

| Command | Measures | Needs |
|---|---|---|
| `uttrflow-dev probe retrieval [--entries N]` | Range scan, `LIKE` and fuzzy matching at three prefilter widths, over a synthetic corpus (default 50,000 entries) | No permission |
| `uttrflow-dev probe surface [--seconds N] [--output report.md]` | What each focused field answers, printed as each new field is seen | Accessibility, and somebody clicking into fields |
| `uttrflow-dev probe tap [--seconds N] [--stall]` | Whether Tab is swallowed and other keys pass; `--stall` sleeps in the callback until the system disables the tap, so the recovery path runs | Accessibility |
| `uttrflow-dev probe ime [--seconds N]` | The marked-text range and input source while composing ([predict-ime.md](predict-ime.md)) | Accessibility |

Accessibility is attributed to the responsible process, so `uttrflow-dev` launched from a terminal
that holds the grant inherits it and `AXIsProcessTrusted()` answers true; the probe says so when it
is refused ("The terminal is what needs permission"). Granting `.build/release/uttrflow-dev`
directly in System Settings › Privacy & Security is the alternative. A keyboard tap can still be
refused after `AXIsProcessTrusted()` returns true, since it may want Input Monitoring; the tap probe
reports that case as "The tap could not be created even though Accessibility is granted."

## Retrieval

`uttrflow-dev probe retrieval`, 50,000 synthetic entries of commands, URLs and phrases, Apple M5
Pro, release build, SQLite 3.53.2; each timing is a median of 100 runs after 20 warm-up runs. The retrieval rows, and a re-take
under load, are in [probe-log.md](probe-log.md#rows).

| Query | Median |
|---|--:|
| SQLite range scan, `text >= 'git c' AND text < 'git d'` | **4.7 µs** |
| Same rows through `LIKE 'git c%'` | 19.8 µs |
| Fuzzy scan, no prefilter | 7,128 µs |
| Fuzzy scan, 6-byte character mask | **478 µs** |
| Fuzzy scan, 12-byte character mask | 1,764 µs |

**The store uses the range scan, not `LIKE`.** `LIKE` is four times slower here for a bare
`LIMIT 8`, and near seventeen times with `ORDER BY count DESC`, because the sort sees every match.
The query plan says why: `LIKE` constrains only the surface id and then filters every row of that
field, so its cost grows with how much one field holds ([predict.md](predict.md), "Two
measurements behind the store's shape").

**Fuzzy is a fallback, never a parallel path.** `git p` matches 925 entries exactly and 2,776
within one edit, and the extra matches are other commands, `git commit` among them. Fuzzy runs only
when the exact scan returns nothing.

**The character-mask prefilter's strength is its window width.** A mask over the first *n + k*
units of an entry, matched to the query's length and edit budget, gives **14.9×**; a fixed 12-byte
window gives 4.0×. A wider window is sound — it never rejects a true match — but loses most of the
gain, so `FuzzyMatch.maskWidth(forQueryOfLength:within:)` takes the query.

**Damerau, not Levenshtein.** `gti c` is one edit from `git commit` only when a transposition costs
one; under plain Levenshtein it is two, and the commonest mistyping would be missed.

## Where a suggestion can be drawn

`SurfaceCapability.placement` decides for one field:

| The field reports | Placement |
|---|---|
| Its text and its caret rectangle (styling optional) | Inline ghost |
| Its text only, with no caret rectangle | Nothing is drawn |
| Nothing, or it is a secure field | Nothing is drawn |

The inline ghost is the only surface. `CapabilitySweep` aggregates readings and compares the share
that reach the ghost with `CapabilitySweep.inlineThreshold` (30%), below which the ghost would not
reach enough fields to be worth leading with.

## The application sweep

`uttrflow-dev probe surface --seconds 240` on macOS 26.5.1 (25F80), MacBook Pro, Apple M5 Pro,
release build: 28 focused elements across 21 applications, each brought to the front with the caret
in one of its fields — a search field, a quick-open field or a message composer, whichever the
application offers without creating a document. The probe reads through
`FocusedFieldReader.snapshot`, the same reader the suggestion loop draws from, so each row says what
the feature does in that field. It asks system-wide first and the application second, because
applications answer one or the other and not reliably both (the same ordering
[insertion.md](insertion.md) records for dictation). Fields are told apart by application, role and
whichever of identifier, placeholder or description the field publishes.

| Application | Role | Field | Value | Caret | Style | Secure | Read | Placement |
|---|---|---|---|---|---|---|--:|---|
| Activity Monitor | AXOutline | Processes | no | no | no | no | 947 µs | nothing |
| Calendar | AXTextField | ToolBarSearchField | yes | yes | no | no | 1428 µs | inline ghost |
| A chat desktop app | AXTextArea | composer | yes | yes | no | no | 1497 µs | inline ghost |
| A second chat desktop app | AXTextArea | composer | yes | yes | no | no | 1494 µs | inline ghost |
| Cursor | AXTextArea |  | yes | yes | no | no | 1456 µs | inline ghost |
| Cursor | AXTextField | Search files... | yes | no | no | no | 1072 µs | nothing |
| Finder | AXOutline | ListView | no | no | no | no | 868 µs | nothing |
| Finder | AXTextField | PathTextField | yes | yes | yes | no | 1288 µs | inline ghost |
| An Electron Git client | AXWebArea |  | yes | yes | no | no | 4228 µs | inline ghost |
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

**46% of focused elements take the inline ghost, above the 30% threshold, so the ghost is the
surface.** Ten of the 28 rows are a window, an outline, a group, a sheet, a static text or a radio
button — what the application answered while no field of its own had focus. Of the 18 rows whose
role a person types into, 13 take the ghost: 72%. 46% is the reach over whatever is focused, 72% the
reach over fields.

**Chrome's own fields take nothing.** Its omnibox and find bar report their text but answer
`AXBoundsForRange` with a zero-size rectangle at the screen's left edge, even with a messaging
timeout forty times longer than the read path allows, so the timeout is not the cause. Safari's
address bar gives a real rectangle. The text-marker and one-pixel-textarea fallbacks
([predict-reliability.md](predict-reliability.md)) are for a Chromium page, and these two fields are
native. Chromium page content is reachable: the Electron Git client's `AXWebArea` answers with a
caret rectangle and takes the ghost.

**Almost nothing answers for styling, and the ghost does not need it.** Only the three AppKit
fields here — Finder's path field, Stickies and TextEdit — describe the font at the caret, as an
`AXFont` dictionary. Terminal does not publish `AXAttributedStringForRange`. The ghost defaults its
face and size elsewhere.

**One reading was slow:** Mail's search field took 73.7 ms against a median near 1.4 ms. The read
path's per-field allowance ([predict.md](predict.md), `FieldReadBudget`) stops such a read, and a
field that keeps overrunning is rested.

The sweep reached every application named in the table. Xcode and Preview were not swept: neither
offers a field to focus without opening a project or a document.
