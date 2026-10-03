# Word error rate

`WordErrorRate` (`Sources/UttrflowCore/Support/WordErrorRate.swift`) is a word-level edit distance
with its alignment kept. The evaluation harness scores recognisers with it, and the app uses the
same alignment wherever it must know whether words survived in order: the meaning guard
(`MeaningPreservationGuard`), the record of what a dictation changed (`DictationChanges`), the
recogniser-loop check (`RecognitionLoop`) and the bake-off scorer (`Scorer`). How the corpus is
scored with it is in [`eval-methodology.md`](eval-methodology.md).

## What it measures

A genuine edit distance over words, not word overlap. A transcript that says other words is wrong
by definition, so a recogniser is scored on the number of edits it takes to repair it; a clean-up
rewrite is scored on similarity instead ([`bakeoff-method.md`](bakeoff-method.md)).

`WER = (substitutions + deletions + insertions) / reference words`. It can exceed 1: a recogniser
that hallucinates a paragraph over a two-word utterance is more than 100% wrong, and clamping to 1
would hide it. An empty reference has no rate: `rate` is `nil` rather than 0%, so the harness
cannot report the flattering answer.

## Why the alignment is kept

A rate says a passage went badly; only the alignment (`match`, `substitution`, `deletion`,
`insertion`, in order) says which words. The fix is usually in the corpus or the normalisation
rather than the recogniser, and that cannot be found from counts.

## The tie-break

`measure(reference:hypothesis:)` is Levenshtein over words with unit costs, then a backtrace that
prefers a diagonal step, then a deletion, then an insertion. The tie-break cannot change the
total, since every optimal path has the same number of edits, but it fixes how a tie is split
between the kinds, so the breakdown never varies between runs.

"Send it to Priya" heard as "send to preeya now" is three edits either way: a deletion, a
substitution and an insertion, or three substitutions. The backtrace reports three substitutions.
So the breakdown is read as "three words wrong here", never as evidence of which kind of mistake
the recogniser is prone to.

## Combining passages

`combined(_:)` sums errors and reference words before dividing, the standard corpus WER, rather
than averaging per-passage rates. Averaging would give a six-word passage the weight of a
sixty-word one, so one stumble over a short sentence could swing the headline more than a whole
bad passage.

## Why it is in `UttrflowCore`

The evaluation harness is never linked into the shipped app: it knows how to reach a private
bucket of recordings, and `Scripts/bundle.sh` refuses a build whose binary carries `UttrflowEval`
symbols. Keeping the algorithm in Core gives the app and the harness one implementation of a
measurement both must agree on, without the app importing the harness.
