# The refresh token in the Keychain: what `KeychainTokenStore` promises

`KeychainTokenStore` (`Sources/UttrflowAccount/TokenStore+Keychain.swift`) keeps the account
refresh token in the macOS Keychain: an update-or-add, a read and a delete, behind the
`TokenStore` protocol in `TokenStore.swift`. Nothing in it can be exercised by a test that
does not touch the login keychain of whoever runs it, so reading it is the review. This page
holds the decisions the code makes and the measurement behind the one that looks like an
over-complication.

| Constant | Value |
|---|---|
| `KeychainTokenStore.defaultService` | `com.uttrflow.session.refresh-token.v1` |
| Account, data-protection keychain | the unix user name (`NSUserName()`), so two people sharing a Mac do not share a session |
| Account, file-based keychain | the unix user name, `·`, and this build's code directory hash in hex |
| `kSecAttrAccessible` | `kSecAttrAccessibleAfterFirstUnlock` |

## Why `kSecAttrAccessibleAfterFirstUnlock`?

The app relaunches at login and refreshes in the background; `WhenUnlocked` fails those and
looks like a spontaneous sign-out. The item is not `ThisDeviceOnly`, so a Mac restored from
an encrypted backup keeps its session, which is what a person expects from a machine that
replaced another.

## Which keychain does the token go to?

The data-protection keychain first (`kSecUseDataProtectionKeychain`), the file-based one
second. Without the data-protection flag the item lands in the file-based keychain, where a
signed build and an unsigned one see different items. It cannot be insisted on: it needs a
keychain-access-group entitlement, that needs a team identifier, and an ad-hoc build (every
local build) has neither. `SecItemAdd` answers `errSecMissingEntitlement` (-34018) and the
sign-in would be lost. Adding the entitlement anyway is worse than not having it: the process
is killed on launch. So both keychains are tried, for writing and for reading, and a token
that lands in neither throws `AccountError.sessionCouldNotBeKept` rather than being
swallowed. A log line (category `account`) names which keychain took the token, never the
token.

A Developer ID build never reaches the fallback: it has a team identifier, so the
data-protection keychain takes the token on the first attempt.

Reading asks both in order, but that does not carry a session across a change of code
identity. The file-based item is named after this build's own code directory hash (below),
so an ad-hoc build, a notarised replacement and the next ad-hoc rebuild each look for a
file-based item under a different name and never find another build's token; a notarised
build also never writes to the file-based keychain. Every changed code identity signs in
again: the fallback isolates builds from each other rather than migrating a session between
them.

## How is a rotated token written?

The server invalidates the token being replaced before `store` runs, so `store` never deletes
before a write is confirmed. It updates the item in the first keychain that takes it (adding
one when there is none), and only then removes the copy in the other keychain, so no
untracked live credential is left behind. A write that fails in both keychains throws and
leaves whatever was stored untouched. `clear()` deletes from both.

## Why is the file-based item named after this build?

The file-based keychain guards each item with an access control list naming the application
that created it, and for ad-hoc code that name is pinned to the code directory hash, which
changes on every build. Pinning the designated requirement to the bundle identifier (what
keeps TCC grants alive across a rebuild) does not help: the keychain's list is not the
designated requirement. Both were measured on macOS 26.5.1 with two ad-hoc builds of one
bundle sharing an item:

    read   -25293  errSecAuthFailed      (a login-password dialog, with UI allowed)
    delete -25244  cannot remove it
    add    -25299  errSecDuplicateItem

One shared name is therefore a trap. The first build to sign in owns the item for ever;
every later build is refused all three operations, and because the write is refused, every
later sign-in ends in `AccountError.sessionCouldNotBeKept` with no way out but deleting the
item by hand in Keychain Access. Suppressing the dialog is not available:
`SecKeychainSetUserInteractionAllowed` is the switch for it, it is deprecated, and this
package compiles warnings as errors.

Naming each build's item after its own code directory hash closes all of it. A rebuild finds
nothing of its own (-25300, no list consulted, no dialog), signs in once, and keeps its
session from then on. Verified by compiling the store into two ad-hoc-signed app bundles
differing only in code hash: one stores, relaunches and rotates; the other reads nil
silently, signs in, and keeps its own; neither disturbs the other; both sign out clean.

A build that cannot read its own code identity gets no file-based item at all, rather than
one that shares a name with another build.

The cost is one stale item per ad-hoc build that ever signed in, which `clear()` cannot reach
because it belongs to another build. They are harmless and visible under the
service name; each run of this removes one, so repeat it until it reports no item:

    security delete-generic-password -s com.uttrflow.session.refresh-token.v1

## Why does `store` throw?

A token that cannot be stored does not cost one sign-in; it costs every sign-in, and from the
user's chair it does not look like a Keychain problem. It looks like signing in does nothing
at all: the empty read that follows is reported upwards as "signed out". Throwing
`sessionCouldNotBeKept` makes the failure visible where somebody can act on it.

## Related

- [account-tests-keychain-adhoc.md](account-tests-keychain-adhoc.md): the tests that pin this behaviour.
- [account-session.md](account-session.md): what the service does with the stored token.
