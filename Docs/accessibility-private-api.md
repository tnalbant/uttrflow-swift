# Accessibility private API

`UttrflowContext` calls the private `_AXUIElementGetWindow` Accessibility symbol to identify the window that owns a focused field. The system framework exports the symbol, but the SDK does not declare it; `FocusedFieldReader+System.swift` declares its ABI locally. This private SPI may change or disappear in a future macOS release, in which case window identification returns no result after the call is unavailable or fails.
