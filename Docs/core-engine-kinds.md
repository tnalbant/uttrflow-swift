# Which transformer kinds a build contains

A transformer is a clean-up engine: it turns a raw transcript into the text that is inserted.
`TransformerKind` in `Sources/UttrflowCore/Models/EngineKinds.swift` names every kind a
configuration can mention, `TransformerKind.selectable` lists the ones compiled into this
binary, and `EngineConfiguration.resolvedTransformerPreference`
(`Sources/UttrflowCore/Models/EngineConfiguration.swift`) filters the stored preference through
it. `TextTransformers.all()` in `Sources/UttrflowAI/TextTransformers.swift` is the one place that
builds the concrete engines.

## Why the preference is filtered

A stored preference can name an engine this binary does not contain: a configuration written
by another build, or the shipped default itself. Unfiltered, the router drops such an entry
silently, so the configuration says one thing and the product does another. The router,
the Settings choices and Diagnostics all read `resolvedTransformerPreference`, so all three
show the order that actually runs.

## The kinds

| Kind | Selectable | Why |
|---|---|---|
| `.foundationModels` | always | Apple's on-device model. |
| `.rules` | always | Deterministic punctuation, capitalisation and filler removal; the floor every preference ends in. |
| `.cloud` | never | No build contains a hosted engine; the case remains only so a stored record or preference naming it still decodes, and the preference drops it. See [`offline.md`](offline.md). |
| `.localModel` | never | See below. |
| `.untidied` | never | Not an engine: it is what a record says when every engine was starved or refused and the transcript went in as heard. |

`EngineConfiguration.default` is `[.foundationModels, .localModel, .rules]` with WhisperKit for
speech; resolved, that is `[.foundationModels, .rules]`.

## Why `.localModel` is never selectable

`TextTransformers.all()` lives in `UttrflowAI`, and `UttrflowAI` cannot import
`UttrflowLocalModel`: that target depends on `UttrflowAI`, and MLX is quarantined there so that
nothing else needs its Metal toolchain. The bake-off (`uttrflow-bakeoff`) reaches the local
model and measures it; no clean-up assembly does.

Hindi does not need it. Apple's model handles Hindi although Apple's own language list omits
it, so `AppleFoundationCleanupModel.verifiedBeyondApplesList` adds it. The measurement is in
[`bakeoff.md`](bakeoff.md), "Apple's model can do Hindi, and Apple does not say so".
