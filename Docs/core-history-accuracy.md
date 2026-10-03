# The "Left as dictated" figure: where its denominator comes from

`DictationPresenter.accuracy(of:)` in `Sources/UttrflowUX/MainDictationPresentation.swift`
draws the figure Home and Insights show as "Left as dictated": the share of the words the user
said that came out as they said them. It reads two values from each dictation's
`RecordedChanges` (`Sources/UttrflowHistory/Corrections.swift`), `spokenWords` and
`correctedWords`, and both are shaped in the history so that figure stays honest.

```
figure = (Σ spokenWords − Σ correctedWords) / Σ spokenWords
```

How the figure is presented, and why it is not called accuracy on screen, is in
[ux-figures.md](ux-figures.md).

## Why `spokenWords` is stored

`DictationRecord.text` is what was *written*. Three passes stand between the utterance and it:
the dictionary can write one word over three, a snippet twelve words over two, and the tidier
drops fillers from what is left. Counting the finished text and calling it the utterance reports
0% to a user whose dictionary is working perfectly. So the count is recorded at dictation time
on `RecordedChanges`, beside the ranges that index into it, and is read together with them or
not at all.

## Absent is not empty

| Stored value | Meaning | Effect on the figure |
|---|---|---|
| `DictationRecord.changes` present, empty lists | The dictation came out exactly as spoken. | Counts in full. |
| `DictationRecord.changes == nil` | Nobody kept a record: a file written without changes, or a dictation whose insertion failed and never reported what was applied (`DictationRecordMapping` stores no changes for a failed dictation). | Left out. |
| `RecordedChanges.spokenWords == nil` | The utterance was not counted, or the stored count was negative. | Left out; `correctedWords` answers zero and is not read. |

Collapsing "absent" into "empty" would let an unmeasured dictation count as a perfect one. The
figure is `nil` when nothing measured remains or nothing was said.

## `correctedWords` counts positions, not ranges

`correctedWords` is the number of distinct positions in `0..<spokenWords` covered by a
correction that is still standing.

- Distinct positions rather than summed range lengths, and out-of-range positions clamped away,
  so the answer is at most `spokenWords` by construction and the figure is a plain subtraction
  with no `max(_:0)` absorbing a disagreement. The pipeline never records overlapping or
  out-of-range corrections (`DictationCorrection.applying(_:to:)` drops them); a hand-edited
  file can carry them, and the figure is then wrong about one dictation rather than negative.
- Undone corrections do not count: the user put those words back, so they read as said.
- Snippets do not count: a snippet fires because the user said its trigger and meant it, so
  charging an expansion against the figure would charge the user's own shorthand.

`CorrectedWordsTests` in `Tests/UttrflowHistoryTests/CorrectionsTests.swift` covers these
rules.
