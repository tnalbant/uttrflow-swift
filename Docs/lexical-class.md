# Reading a word's class

Every seam decision that asks what kind of word a word is reads it from one place:
`LexicalClass` in `Sources/UttrflowCore/Cleaning/LexicalClass.swift`, a thin wrapper over
Apple's on-device `NaturalLanguage` lexical-class tagger. `WordSlot`, `MentionGuard` and
`LayoutWordsPass` call it; nothing else builds its own tagger.

This is the lexical-class layer of the planned clause analyser. Sentence completeness and
clause boundaries are not built yet.

## How far the tagger holds on bare recogniser text

The question is whether the tagger still gives the same classes when the text arrives
lowercase and without marks, as bare recogniser output does.

**Method.** Each English reference in `EvaluationCorpus` that is plain ASCII is tagged as
written. It is then lowercased, with `. , ? ! ; : " ( )` replaced by spaces, and tagged again.
Cases whose word count changes are left out. The written tagging is the reference, so this
measures how stable the tagger is, not whether it is right.

| Measure | Words | Same class | Agreement |
|---|---|---|---|
| Lowercase, no marks, every word | 2215 | 2145 | 96.8% |
| Lowercase, no marks, word that closes a sentence | 294 | 275 | 93.5% |
| Cased, no marks, every word | 2215 | 2178 | 98.3% |

341 of 359 references aligned. The most common change is noun read as verb (18 words), then
noun read as other word or interjection (6 each).

Measured on an Apple M5 Pro running macOS 26.5.1, with a standalone `swiftc` probe. The same
numbers are checked by `Tests/UttrflowEvalTests/LexicalClassProbeTests.swift`, which fails
below 95% word agreement.

**What it does not decide.** The word that closes a sentence is the one a seam decision reads
most, and that is where agreement is lowest. Whether 93.5% is good enough to read completeness
from the tagger, or whether a rule table held as data is needed, has not been decided.
