# Which transformer kinds a build contains

`TransformerKind.selectable` lists the kinds compiled into this binary, and
`EngineConfiguration.resolvedTransformerPreference` filters a stored preference through
it. Without that filter a preference naming an engine the binary does not contain is
silently dropped at routing time, so the configuration says one thing and the product
does another.

- `.cloud` is never selectable. No build contains a hosted engine; the case remains only so
  a stored record or preference naming it still decodes, and the preference drops it.
- `.localModel` is never selectable, whatever build flags are set. `TextTransformers.all()`
  lives in `UttrflowAI`, and `UttrflowAI` cannot import `UttrflowLocalModel` — that target
  depends on `UttrflowAI`, and MLX is quarantined there so that nothing else ever needs its
  Metal toolchain. The bake-off reaches the local model and measures it; no clean-up
  assembly does.
- Apple's Foundation Models handle Hindi. This is undocumented but verified, so the
  language the local model was brought in for is covered without it.
