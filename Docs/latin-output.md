# Latin letters only

**Uttrflow writes English/Latin script only. Hindi and Hinglish speech is romanised the way
people type it, never written in Devanagari and never translated.**

"हाँ ठीक है" is written "Haan thik hai", not "हाँ ठीक है" and not "Yes, okay". Uttrflow is not
a translator. This holds for every piece of text dictation inserts, whichever engine tidied
the words, and when no engine tidied them at all.

Three places make it true, from the most specific to the last resort.

| Where | What it does |
|---|---|
| `RuleBasedTransformer` | romanises the transcript with `Romaniser` before the passes run, so the floor beneath every model writes Latin letters |
| `MeaningPreservationGuard.scriptVerdict` | refuses a model's rewrite that is in another script, translates a Devanagari draft, or repeats a worked example, so the router falls back to the rules |
| `DictationPipeline` | runs `LatinScript.enforced` over the finished message and again after snippets, immediately before insertion, so untidied text and user-authored expansions are romanised too |

Snippet expansions stay stored exactly as the user wrote them. The final script check runs
after expansion, so a snippet written in Devanagari is inserted romanised in Latin letters.

Recognition still answers in Devanagari, and what that costs in decoder steps — with the options
for decoding straight to Latin, and why none of them is taken — is measured in
`Docs/speech-engines.md`.

## The romaniser

`Sources/UttrflowCore/Script/Romaniser.swift` writes Devanagari the way Hinglish is typed in a
chat, not the way a scholar transliterates it. It has no diacritics and never produces
"karanā"; it produces "karna".

- **Common spellings first.** A table of 170 frequent words holds the
  spelling people actually use: है hai, हाँ haan, ठीक thik, नहीं nahi, मैं main, में mein, क्या
  kya, क्यों kyun, हूँ hoon, and loanwords people write in English (ऑफिस office, मिनट minute).
  Chandrabindu and anusvara key the same entry, so हाँ and हां meet.
- **Syllables otherwise.** A word is split into consonant clusters and their vowels.
- **The unwritten vowel is dropped** at the end of a word (कल kal) and between a vowel and a
  consonant that carries its own vowel (करना karna, समझना samajhna), scanning from the right.
  A nasal syllable before it keeps it too (ज़िंदगी zindagi). A conjunct after it keeps it:
  अनन्या is "ananya", not "annya".
- **Long vowels are doubled only where people double them.** आ is "aa" in a first or closed
  syllable (आज aaj, किताब kitaab) and "a" at the end of a word or before another vowel
  (करना karna, जाएगा jayega). ई and ऊ are "ee" and "oo" in a closed syllable or a first
  syllable before "a" (चीज़ cheez, पूरा poora), otherwise "i" and "u" (लीजिए lijiye, दूँगा dunga).
- **A final cluster drops its vowel too** (अगस्त agast, दोस्त dost) unless it ends in य, र or व
  (मित्र mitra).
- **Nasalisation is "n"**, "ein" for a final ें (में mein), and nothing before न or म (मैंने maine).
- **An unwritten vowel before a closing ह is "e"**: पहले pehle, कह keh.
- **Clusters people write as one sound**: च्छ cch (अच्छा accha), क्ष ksh, ज्ञ gy. व is "w" except
  before "i" or "e" (वाला wala, विक्रम vikram). Nukta letters take their borrowed sound: ज़ z, फ़ f.
- **Devanagari digits and stops** become Western digits and a full stop; a danda the recogniser
  followed with a Latin stop is written once.

Nothing in the Devanagari block survives it: every scalar of the block, alone or after a
consonant, is covered by a test.

### Measured

Against the twelve Hindi and Hinglish passages of `TranscriptionCorpus`, whose Devanagari and
romanised forms are word-for-word parallel (385 words), normalised as every transcription score
is (`TextNormaliser.standard`):

| | words | characters |
|---|---|---|
| ICU letter by letter, stripped of diacritics | 42.7% | 84.5% |
| `Romaniser`, syllable rules alone (no table) | 91.9% | 98.3% |
| `Romaniser` | **97.9%** | **99.4%** |

The rules and the table were written with these passages in view, so these are upper bounds:
there is no held-out Hindi set yet. The clean-up corpus's six Hinglish cases were in view too;
against their expected text, which also has fillers removed and commas added, the romaniser
alone matches 92.9% of words and 97.4% of characters. `RomaniserCorpusTests` holds the floor.

The remaining misses are mostly two spellings of one word, where neither is wrong: the
references write "theek" and "hun" where the table writes "thik" and "hoon", "Are" where it
writes "arre", "zaroorat" where the rules write "zarurat", "raghunath" for "raghunaath".

On the rules path, the six Hinglish cases of the clean-up corpus went from 0 passing (mean
similarity 24%) to 5 passing (92%). The sixth, `hinglish-negation-kept`, expects "yah" and
"theek" where the table writes "yeh" and "thik". English is unchanged byte for byte: every
English case of the clean-up corpus gets the answer the passes gave before romanising existed,
and `LatinScript.enforced` returns every English passage and expectation exactly as written.

### Audited by sound class

`RomaniserSoundClassTests` checks the romaniser by the structure of the script rather than by
reported word: every consonant with every vowel sign in a closed first syllable (30 × 11 = 330
cases), independent vowels, common conjuncts (क्ष, त्र, ज्ञ, श्र and doubled stops), final
halant, anusvara before each consonant class, chandrabindu, nukta letters, visarga and digits,
and, separately, unwritten-vowel cases, which need a rule rather than a table. Each case is
compared with the form people type; the expected forms are compiled for this audit, not copied
from any external list.

A case written wrongly today is listed in `knownGaps` and recorded as a known issue, so a fix
shows up as an unexpected pass and the list must shrink with it. Measured on the tree this
audit landed on:

| Class | Cases | Wrong | Written today |
|---|---|---|---|
| consonant × vowel sign | 330 | 0 | |
| independent vowel, conjunct, final halant, nukta, digit | 40 | 0 | |
| anusvara before velar, palatal, retroflex, dental, sibilant | 15 | 0 | |
| anusvara before a labial | 6 | 6 | मुंबई munbai, नंबर nanbar, संपर्क sanpark |
| chandrabindu | 6 | 3 | माँ man, गाँव gaanw |
| visarga after an unwritten vowel | 4 | 3 | अतः ath, नमः namh |
| unwritten vowel | 13 | 4 | दोपहर dophar, जनवरी janawri, चाय chaay, हँसना hansana |

Each wrong row is a class, not a word: anusvara is always "n" though it is said "m" before
प फ ब भ म; a nasal "aa" that is the whole word is shortened as if it ended a longer word; a
visarga after the unwritten vowel drops the vowel it follows; and the unwritten-vowel rule
drops the vowel before a final ह cluster and keeps the one a final य or व carries.

## The script guard

A model can answer Devanagari with a translation, with the prompt's own worked example, or in
another script, and before this check the guard accepted all three (issue 700): its tokeniser
reads no Devanagari, so it compared nothing.

`scriptVerdict` reads the draft the only way it needs to: romanised by `Romaniser`.

- **Another script.** A rewrite holding any letter outside Latin is refused.
- **A translation.** When the draft holds Devanagari, each word of the rewrite is looked for
  among the romanised draft's words by `Romaniser.soundKey`, which folds the usual spelling
  variants together ("theek" and "thik", "woh" and "wo", "hoon" and "hun"). Digits are left to
  the number checks. More than half the rewrite's words with no counterpart is a translation.
  Measured on the answers issue 700 recorded: "Meeting is at four o'clock, no no, five o'clock."
  has 8 of 9 words with none and is refused; "Woh kya hai na, yaani mujhe thoda time chahiye."
  has 1 of 9 and is accepted.
- **A changed word.** Below that, the rewrite's content words are aligned with the romanised
  draft's, in order, by `WordErrorRate.measure` over the same sound keys, with number words read
  as their digits, fillers dropped and a word said twice in a row kept once (issues 2087 and
  2416). Grammar words (Hindi auxiliaries, postpositions and particles, and English
  `FunctionWords`) are left out of both sides; a negation, a number and a Hindi pronoun never
  are. A dropped or added content word refuses the rewrite, and so does a substituted one unless
  it is:
  - the same word in another form, by `WordForms.sameRomanisedForm`: an English
    inflection by `sameForm`, a Hindi verb or noun and its ending ("aa" and "aata", "log" and
    "logon"), or two cases of one demonstrative ("yah" and "is");
  - an English loanword the rules romanised, written in its English spelling: the two share a
    Double Metaphone key of at least two sounds and are not two ordinary English words
    (`ReadingRestraint.isOrdinaryCollision`). "ticket" for "tikat", "cancel" for "kainsal",
    "office" for "ophis" and "sorry" for "sauri" are accepted.

  "Maine khana khila." for "मैंने खाना खा लिया" changes the verb and drops "liya", and "Hum doh
  baje" for "हम धाई बजे" changes the time: "dhai" and "doh" share only a lone T, which says too
  little to call them one word. Both are refused and the rules' romanisation goes in. What this
  cannot see: a change of tense on a verb whose stem is kept ("aata" for "aa raha") is accepted,
  and a changed Hindi word that happens to share a two-sound key with the draft's is too.
- **A worked example.** A rewrite of three or more words, at least 80% of them one example's
  words in order, is refused when the draft holds fewer than half of that example's words.
  This reads any script, so an English example given back for English that did not say it is
  refused too, while a dictation that really says "add milk and eggs to the shopping list" is
  not.

A refusal is not a failure. The router moves on, the rules romanise the draft, and the words
arrive in Latin letters.

## The last resort

`LatinScript.enforced` runs over the finished message. Devanagari is romanised, with a capital
where a romanised word opens a sentence. Any other script is written in Latin letters through
ICU with its diacritics stripped, and a letter ICU cannot write is dropped rather than inserted.
Another script's decimal digits become Western ones.

What counts as Latin is deliberately wide, because English text is full of it: accented Latin
letters, combining diacritics, curly quotes and dashes, currency, superscripts, letter-like
symbols, ligatures, fullwidth Latin, and emoji with their variation selectors, skin tones and
keycaps are all left exactly as they were. Only letters and marks of another script change.
