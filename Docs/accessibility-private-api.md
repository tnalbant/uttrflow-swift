# Accessibility private API

Uttrflow calls one private Accessibility symbol, `_AXUIElementGetWindow`, to find the window
number that owns a focused field. The ApplicationServices framework exports the symbol but the SDK
does not declare it, so each caller declares its ABI locally with `@_silgen_name`:

| File | Used for |
|---|---|
| `Sources/UttrflowContext/FocusedFieldReader+System.swift` | the window of the field a suggestion is read from, which tells apart same-app windows with identical fields |
| `Sources/UttrflowInput/SystemInput.swift` | `AXAccessibilityFocus`'s window reads, which `SuggestionAcceptor` uses to check that a suggestion is written into the window it was read from |

The symbol is private and can change or disappear in a later macOS release. Both callers treat any
result other than `.success` as "the window cannot be identified" and return `nil`.

Related: [context-accessibility.md](context-accessibility.md), [insertion.md](insertion.md).
