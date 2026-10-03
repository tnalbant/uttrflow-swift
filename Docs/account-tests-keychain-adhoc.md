# Ad-hoc-signed builds and the data-protection keychain

`SecItemAdd` against the data-protection keychain answers `errSecMissingEntitlement` for an
ad-hoc-signed build (`codesign --sign -`). That keychain needs a keychain-access-group
entitlement, which needs a team identifier an ad-hoc signature does not carry, and every local
build and test runner is ad-hoc-signed. So `KeychainTokenStore`
(`Sources/UttrflowAccount/TokenStore+Keychain.swift`) tries the data-protection keychain first,
then the file-based keychain under an account name pinned to this build's code hash, and throws
`AccountError.sessionCouldNotBeKept` when neither takes the refresh token rather than reporting
success. A store that swallowed the `OSStatus` would leave the next launch with no credential
and no explanation. `Docs/account-keychain.md` has the store's own rules; this page is what the
tests pin.

## What the tests pin

All in `Tests/UttrflowAccountTests/`:

- `KeychainFallbackTests`: a store that cannot keep the token throws `.sessionCouldNotBeKept`
  instead of succeeding; the error is catalogued as blocking with retry offered; and the real
  store round-trips, rotates and clears through whichever keychain the runner's signature
  allows. Which keychain took the token is a property of the signature, not the code, so it is
  not asserted.
- `HTTPAuthenticationServiceTests.noCredentialIsNotASignOut` and
  `AccountRefreshTests.noCredentialIsNotASignOut`: a Mac holding no refresh token answers
  `ProfileRefresh.noCredential`, never `.signedOut`. A `.signedOut` answer makes
  `AccountRefresh` delete a cached profile the server still honours, which shows as "Not signed
  in" immediately after a completed sign-in.
- `HTTPAuthenticationServiceTests.anEmptyTokenStoreKeepsTheProfile`: the same rule end to end,
  with a real service and a real `AccountRefresh` over an empty `InMemoryTokenStore`. It proves
  the empty-store contract, not the real-Keychain path `KeychainFallbackTests` owns.

Related: `Docs/account-keychain.md`, `Docs/packaging.md` (why local builds are ad-hoc).
