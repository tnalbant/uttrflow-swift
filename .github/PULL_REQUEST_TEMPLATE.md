<!--
Thank you. A few things that make review quick — none of them are forms to fill in for
their own sake, and if one does not apply to your change, delete it.
-->

## What this changes, and why

<!-- The why matters more. If you tried an obvious approach first and it did not work,
that is the most useful sentence you can write here — it stops the reviewer proposing it. -->

## How you know it works

<!-- Which test covers it, or what you did by hand and what you saw. -->

For changes to `Sources/UttrflowAI/PromptBuilder.swift` or the rules, include the
`make bakeoff ARGS="--against <saved-result.json>"` comparison output, or explain why a
corpus comparison could not be run.

---

- [ ] `make verify` passes locally (lint, PII audit, build, tests, coverage floor, offline audit)
- [ ] New behaviour has a test, or there is a reason in the PR why it cannot
- [ ] No real email address, postal address or personal data in fixtures — `example.com` and invented streets
- [ ] Comments are one line, present tense, and describe what the code does now

Add a reason only when it changes what a reader should do. Put durable measurements or
architectural rationale in `Docs/`; put development history in this description or the commit.

<!--
If this is a draft or an idea you want a view on before finishing, open it as a draft and
say so. That is welcome and is cheaper than building the wrong thing.
-->
