# UX test harness traps

Two harnesses in `Tests/UttrflowUXTests/` drive whole flows rather than single functions:
`PanelEndToEndTests` runs a real `ClipboardStore` under a bound quick panel, and
`OnboardingSupport.swift` holds the doubles and `Harness` the onboarding tests drive. Each has
one rule that is not obvious from the code.

## The end-to-end harness owns no lifetime

`PanelEndToEndTests.Harness` is a plain struct with no `deinit`, and each test removes the
temporary folder with `defer { harness.cleanUp() }`.

A `~Copyable` harness whose `deinit` deletes the folder crashes: every method on it is
`await`ed, so its lifetime ends at the last syntactic use rather than at the end of the test,
and the deallocation lands *during* an in-flight call on the store. The symptom is a
segmentation fault deep in `Sequence.first(where:)` or `seed(_:)`, over memory freed underneath
them, and it depends on layout: one unused property added to `ClipboardStore` is enough to
trigger it. Making the harness a class does not help; the deallocation only moves.

The rule: nothing in a test harness may own a lifetime that an awaited call depends on. Write
the clean-up down at a point in time (`defer { harness.cleanUp() }`) rather than inferring it
from a value going out of scope.

## Onboarding doubles are gated, not raced

`Gate` in `OnboardingSupport.swift` holds a call open so a test can act while a download or a
sign-in is in flight, and `GatedInstaller` drives a model download one instruction at a time
so mid-download states are reached on purpose. Proving the flow's generation
guards work means being *inside* the call when the user walks away, which a test cannot reach
by winning a race. `settle(until:)` yields rather than sleeps, because there is no wall clock
anywhere in the flow to wait on.

`FakeAuthenticationService` is gated by default, so `Harness.choose(_:)` leaves the flow
waiting on a browser. A test that wants the sign-in to finish calls `returnFromBrowser()`,
which waits for the call to reach the gate before opening it: a gate nothing has reached yet
would open for nobody.

Related: `Docs/preferences-suites.md` (real `UserDefaults` in tests),
`Docs/account-tests-keychain-adhoc.md` (real Keychain in tests).
