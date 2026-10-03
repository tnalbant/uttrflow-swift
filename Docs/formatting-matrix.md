# Formatting coverage matrix

Generated from the `classes` tags in `EvaluationCorpus`; do not edit by hand.
Regenerate with `UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter FormattingMatrixTests`.
A class is covered at 5 tagged cases, partial below that, uncovered at none.

| Class | Cases | Coverage | Case ids |
|---|---|---|---|
| sentence-boundaries | 7 | covered | `fmt-boundary-two-statements`, `fmt-boundary-run-on-three`, `fmt-boundary-stray-stop-mid-clause`, `fmt-boundary-single-word`, `fmt-boundary-so-joins-clause`, `fmt-question-after-statement`, `fmt-hinglish-two-sentences` |
| commas | 7 | covered | `fmt-boundary-so-joins-clause`, `fmt-comma-vocative`, `fmt-comma-introductory`, `fmt-comma-but-clause`, `fmt-comma-yes-answer`, `fmt-comma-none-in-short-clause`, `fmt-list-inline-series` |
| questions | 6 | covered | `fmt-question-can-you`, `fmt-question-what-time`, `fmt-question-after-statement`, `fmt-question-tag`, `fmt-question-indirect-is-statement`, `fmt-hinglish-question` |
| quotes-and-brackets | 5 | covered | `fmt-quote-said`, `fmt-quote-open-close`, `fmt-bracket-aside`, `fmt-paren-aside`, `fmt-quote-noun-stays` |
| ellipses | 5 | covered | `fmt-ellipsis-spoken-dot-dot-dot`, `fmt-ellipsis-named`, `fmt-ellipsis-from-recogniser`, `fmt-ellipsis-trailing-off`, `fmt-ellipsis-not-invented` |
| capitalisation-and-tokens | 5 | covered | `fmt-token-pronoun-i`, `fmt-token-email-address`, `fmt-token-web-address`, `fmt-token-acronym-kept`, `fmt-token-mixed-case-brand` |
| numbers | 8 | covered | `fmt-number-count`, `fmt-number-percent`, `fmt-number-time`, `fmt-number-money`, `fmt-number-one-as-pronoun`, `fmt-list-count-not-list`, `fmt-correction-actually`, `fmt-hinglish-number` |
| lists | 5 | covered | `fmt-list-numbered-spoken`, `fmt-list-first-second-third`, `fmt-list-inline-series`, `fmt-list-bullet-command`, `fmt-list-count-not-list` |
| paragraphs | 5 | covered | `fmt-paragraph-new-paragraph`, `fmt-paragraph-new-line`, `fmt-paragraph-two-breaks`, `fmt-paragraph-next-line`, `fmt-paragraph-noun-stays` |
| corrections | 5 | covered | `fmt-correction-no-wait`, `fmt-correction-i-mean`, `fmt-correction-actually`, `fmt-correction-stammer`, `fmt-correction-i-mean-it-stays` |
| per-destination | 5 | covered | `fmt-destination-messaging-no-stop`, `fmt-destination-terminal-command`, `fmt-destination-spreadsheet-cell`, `fmt-destination-email-sentence`, `fmt-destination-document-sentence` |
| code-and-markdown | 5 | covered | `fmt-code-snake-case`, `fmt-code-camel-case`, `fmt-code-file-name`, `fmt-code-version`, `fmt-code-markdown-heading-kept` |
| hinglish | 5 | covered | `fmt-hinglish-question`, `fmt-hinglish-statement`, `fmt-hinglish-number`, `fmt-hinglish-two-sentences`, `fmt-hinglish-already-latin` |
