# The figures on Dictation, Insights and Diagnostics

The main window's pages show figures about the user's dictation. `DictationPresenter` in
`Sources/UttrflowUX/MainDictationPresentation.swift` computes the Dictation page's rail figures;
`InsightsPresentation.swift` reuses the same arithmetic, and Home's tiles share the measures (see
[`app-main-window.md`](app-main-window.md#home)). The rule for every figure: nothing is shown that
was not measured. There is no "time saved" tile because Uttrflow never watches the user type.

## Left as dictated

`DictationPresenter.accuracyTitle` is "Left as dictated", captioned "The share of your words the
clean-up left exactly as you said them. It does not say whether they were heard correctly." Both
halves of the fraction count *spoken* words and both are read out of the same value:

```
leftAsDictated = (spokenWords - correctedWords) / spokenWords
```

`RecordedChanges.correctedWords` (`Sources/UttrflowHistory/Corrections.swift`) counts distinct
positions within the utterance, so the subtrahend cannot exceed the denominator whatever is on
disk. There is deliberately no `max(_, 0)` under the division: a clamp there would turn a units
mismatch, such as finished-text words as the denominator against heard words as the subtrahend,
into a plausible-looking zero.

Only measured dictations count. A dictation whose insertion failed reports no changes (nobody was
keeping a record), and counting its words in the denominator while its corrections cannot appear
in the numerator would report a figure higher than the truth. A dictation whose `spokenWords` is
`nil` is left out on the same grounds. The figure is `nil` when nothing has been measured or
nothing was said.

The caption says "as you said them", not "as you wrote them": the denominator is the utterance, so
a dictation the dictionary improved is not penalised for coming out shorter.

**It is not accuracy, and it does not say it is.** The fraction measures how little the clean-up
altered the transcript, and a recogniser that mishears a word the clean-up then leaves alone scores
it 100%. [`measuring-accuracy.md`](measuring-accuracy.md) and `UttrflowEval` are where accuracy is
defined, against a read corpus, and the two must not share a word.

There is no baseline beside it. The figure is near enough 100% for everybody every day, so
yesterday's copy of it would be a second bar of the same length: a comparison that cannot differ
tells the reader nothing.

## Pace

Words per minute is pooled across every timed dictation (total words over total seconds), not
averaged per dictation, so a two-word aside does not weigh as much as a two-minute paragraph. `nil`
when nothing was timed.

## Streak

A streak is current only when the most recent dictation was today or yesterday; a run ending
earlier shows no streak (the Home tile reads "0 days", and the Dictation and Insights figure is
omitted). Yesterday still counts because the day is not over yet.

A streak that merely reaches the oldest entry the app happens to have is not evidence of anything:
a new user's whole history is "the oldest thing kept". The caption "at least — anything older has
been deleted" appears only when the snapshot still carries an entry retention drops, on the run's
oldest day or the day before it; that entry is the evidence that the run went further back than
what is shown. A run that merely fills the retention window proves nothing, since a new install
dictating every day for its first week fills it too. Short of that evidence, the caption reads
plainly: "days in a row".

## Comparisons

The Dictation page compares today against earlier days once there is at least one
(`DictationPresenter.comparisonFloor`, 1). The "Words dictated" figure is the total within the
retention window and is never called a lifetime total, because older words are gone and cannot be
counted.

## The Insights calendar

Insights draws the chosen range (`InsightsRange`: 7, 30 or 90 days, today last) as weeks of tiles
starting on the calendar's own first weekday. A tile's teal is
`0.15 + 0.85 × words ÷ busiest day's words` (`InsightsCalendarDay.shade`), so a quiet day still
reads as spoken on and the busiest is full strength; a day with nothing said is a bare tile. The
figures beside it are the range's words and dictations, the pooled pace above, and the streak Home
counts, so the two pages cannot disagree. How the day numbers stay legible on every shade is in
[`redesign-tokens.md`](redesign-tokens.md#the-insights-calendars-day-numbers).

A range longer than history is kept cannot be picked: it would be a calendar of days whose
transcripts are already deleted. A week is always offered, and the page opens on a month where
history reaches that far. Before either, the page waits for
`InsightsPresenter.daysBeforeCharting` (7) days spoken on, because a baseline drawn from three days
is noise.

## Diagnostics

Diagnostics follows the same rule. Its reliability rows are built from `PipelineStage.allCases`
and a stage with no samples gets no row (`DiagnosticsPresentation.reliability`), so a stage
appears by itself once something measures it and never shows as zero. Memory use, a p95 and a
time-saved figure are not drawn, because nothing measures them.
