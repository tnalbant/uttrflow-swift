# Main window: sizing, colours, Home and the clipboard demonstration

The main window holds Home, History, Insights, the clipboard pages and Settings. Its window is
`MainWindowController` and its views are in `Sources/Uttrflow/Main/`, with sizes in `MainMetrics`
(`MainPieces.swift`); every colour is in `Sources/Uttrflow/Brand/BrandPalette.swift`; what Home
draws is decided by `HomeDashboard` in `Sources/UttrflowUX/`. Related:
[`redesign-tokens.md`](redesign-tokens.md) for the token set,
[`startup.md`](startup.md) for Home's speech-model status.

## Window sizing

`MainWindowController.makeWindow()` sets `hosting.sizingOptions = []`. `NSHostingView` otherwise
reports SwiftUI's ideal size as its intrinsic content size and AppKit resizes the window to match,
so the window would grow and shrink as the user moved between pages, with long pages several
screens tall and their content sitting at the top of a mostly blank window. The pages scroll
instead.

| Value | Points | Constant in `MainMetrics` | Why |
| --- | --- | --- | --- |
| Default size | 1180 × 780 | `windowSize` | 900 × 620 is cramped once the rail carries four figures |
| Minimum size | 760 × 500 | `minimumWindowSize` | |
| Sidebar, icons only | 88 | `iconRailWidth` | a 44-point target with room either side, wide enough that the zoom button, whose right edge sits at 79 points, stays inside the island |
| Sidebar, names showing | 232 | `sidebarWidth` | six rows of 14-point text, the "Your words" heading and the account card |
| Figures rail | 186 | `railWidth` | at 76 points "Words per minute" wraps one word to a line and "2.7K" truncates |

The sidebar is a dark island floated 10 points off the window's edges. Its expanded state is
remembered in `UserDefaults` directly, not the settings store: it is the window's own memory of
how it was left, like the quick panel's position. With nothing remembered, as on a first launch,
the sidebar opens with its names showing.

## Colours

`BrandPalette.swift` is the only place a colour is defined. It groups every value by role (brand
teal, brand purple, surfaces, lines, text tones and semantic colours), each as a dark and light
pair (`BrandTone`) where the appearance changes it, and some with a high-contrast pair for
Increase Contrast. Views name a palette member, through aliases such as `Color.panelAccent` or
`Color.mainBackground`; none writes a hex. Where two views draw the same value they point at the
same member, so the floating button's live accent and the quick panel's accent cannot drift apart.
`NSColor.orbit(_:)` in `Sources/Uttrflow/Main/OrbitPalette.swift` resolves a pair per appearance,
including Increase Contrast. `BrandPaletteTests` pins the primary teal and secondary purple.

Text that carries a status is drawn in an ink, never in a fill. The semantic fills (`warning`,
`success`, `recording` and the teal `deep`) are bright single values that sit near 2:1 on a light
card, which is fine for a dot, an icon or a filled button and unreadable as words. The inks
`Semantic.warningInk`, `successInk`, `criticalInk` and `Teal.ink` are pairs that clear 4.5:1 on a
card, on the ground and on their own 16% pill wash in both appearances, reached as
`Color.warningInk`, `successInk`, `criticalInk` and `accentInk` and through `MainTone.foreground`.
`SemanticInkContrastTests` computes those ratios, so a palette edit that drops one below 4.5:1
fails.

The three greys text is drawn in (`Text.primary`, `muted` and `dim`) clear 4.5:1 on all four
surfaces text sits on, the rail included, in both appearances. The rail is the darkest light
surface, and it carries the sidebar's version and badge counts, so it sets the floor: `dim` is
`6D6481` in the light, which puts it within a few steps of `muted`. That is the room the ramp has:
a fourth readable grey does not fit between `muted` and the rail, so `Text.ghost` is a mark rather
than a word and is held to 3:1. `TextToneContrastTests` computes every one of those ratios and
fails below the floor.

## Home

`HomeDashboard` decides everything the page draws; the views only lay it out.

- **Mood** (`HomeMood`). The hour picks one of six parts of the day (05–08 early morning, 08–12
  morning, 12–17 afternoon, 17–20 evening, 20–23 night, 23–05 late night) and with it the greeting
  ("Working late" from 23:00) and the picture in `Sources/Uttrflow/Resources/Mood/` beside the
  hero. The page redraws at the next boundary hour or midnight (`HomeMood.nextBoundary`).
- **Tiles.** Words today; the streak, days in a row with a dictation ending today or yesterday,
  since a day not over yet has not broken it; pace, pooled over every timed dictation kept; and the
  share left as dictated, the same measure the Dictation page uses: spoken words the clean-up kept
  as said, over every measured dictation kept. A figure with nothing measured behind it is a dash.
  The rings fill at `dailyWordGoal` (1,000 words), `streakGoal` (7 days), `paceGoal` (150 words a
  minute, an ordinary conversational rate) and 100%.
- **Recent activity.** The `activityShown` (3) newest dictations. The tag says what the clean-up
  did, "As dictated" or "N changes", counting corrections still standing and snippets, and a
  dictation that was never measured has no tag, so nothing is claimed about it.

## The clipboard demonstration

`ClipboardDemonstration` is drawn rather than recorded. A recorded animation is a few hundred
kilobytes that has to be re-recorded every time the panel's design moves, is wrong the moment
somebody changes their shortcut (this reads the real one), is soft on a Retina display, and cannot
follow the light or dark appearance.

It shows the whole gesture, ending with the words arriving in the document; stopping when the
panel closes would demonstrate a mechanism and leave out the payoff.

| Value | Constant | Why |
| --- | --- | --- |
| 8 s loop | `ClipboardDemonstrationPhase.loop` | long enough to read the pasted line before it resets |
| 410 pt document | `ClipboardDemonstrationMetrics.documentWidth` | the finished sentence measures 383.6 points at the footnote size, plus ten points of padding a side; a line that wrapped would read as a paragraph appearing |
| 17 pt padding, 22 pt gap | `padding`, `columnSpacing` | |
| 360–460 pt words | `explanationMinimumWidth`, `explanationMaximumWidth` | |
| 30 frames a second | `MotionBudget.demonstrationFrameInterval` | the most the clock wakes while the panel moves |

- **Layout.** Side by side while the document can hold its line, stacked otherwise. The card is
  offered a width, `onGeometryChange` records it, and
  `ClipboardDemonstrationMetrics.arrangement(forOfferedWidth:)` answers from it: side by side once
  17 points of padding a side, 22 of gap, the document's 410 and 360 for the words all fit (826
  points), with the words widening to 460 and no further. At the 760-point minimum window,
  reserving 410 for the document leaves 294 for the words beside it, which is why the stacked form
  exists. `ViewThatFits` is not used for this choice: it asks every candidate how big it would like
  to be, and inside the clock's closure that measured both arrangements on every display frame
  (see [`performance.md`](performance.md)). The decision is width in, arrangement out, and the
  clock only draws.
- **A pure function of the clock**, so the page can redraw underneath it (on every keystroke in a
  search field) without the loop stuttering.
- **Moves only when it is seen.** Only while its window is key in the active app and some of the
  card itself is inside the scroll view's bounds and on a display, per `WindowAttention`, and only
  while `MotionBudget` finds no Reduce Motion, Low Power Mode or serious thermal pressure; otherwise
  it rests on the panel open with the address row chosen. Its clock wakes only when the drawing
  changes (`ClipboardDemonstrationMoments`).
