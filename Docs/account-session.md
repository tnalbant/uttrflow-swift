# The account session: what `HTTPAuthenticationService` promises

`HTTPAuthenticationService` signs a person in against the account backend and keeps them
signed in: it starts a sign-in (browser with a loopback redirect, or device code), exchanges
the result for a session, renews the access token, reads the profile, fetches the avatar and
signs out. It lives in `Sources/UttrflowAccount/HTTPAuthenticationService.swift`, behind the
`AuthenticationService` protocol in `AuthenticationService.swift`; the loopback listener is
`LoopbackListener+System.swift`. `Sources/Uttrflow/Onboarding/OnboardingAccountLayer.swift`
picks it for a build whose Info.plist names a backend (`UttrflowBackendURL`) and whose
entitlement key is configured; any other build gets `InMemoryAuthenticationService`, a
stand-in that signs in on the Mac with no network. The code says what each call does; this
page says why the rules are the way they are.

| Constant | Value | Meaning |
|---|---|---|
| `HTTPAuthenticationService.renewalMargin` | 60 s | an access token this close to expiry is renewed before use |
| `HTTPAuthenticationService.defaultClientID` | `uttrflow-mac` | the registered client identifier; not a credential, PKCE covers it |
| `SystemLoopbackListener.connectionLimit` | 32 | connections one sign-in attempt accepts |
| `SystemLoopbackListener.maxRequestBytes` | 8192 | bytes one callback request may accumulate before it is parsed as is |
| `SystemLoopbackListener.callbackPath` | `/callback` | the path the browser redirect arrives on |

## Is a failed request a refusal?

No. The transport throws only when no response arrived, and the service turns that into
`AccountError.serverUnreachable`. Every answer the server gave, including `401` and `502`,
comes back as a response. That distinction is the offline promise: a Mac that cannot reach
the server keeps its cached profile, and a Mac that has been *told* its session is over does
not. See [account-transport.md](account-transport.md) for how the transport draws the line.

A `5xx` is not treated as unreachable. The server was reached and it failed; calling that
"no connection" would send the user to check their Wi-Fi over an outage they cannot do
anything about, and would hide the outage. It surfaces as `AccountError.providerRefused`.

A refusal's decoded explanation is returned to the caller so a person can act on it. The account
log records only a fixed failure reason and the HTTP status, never the server-provided text. A
response that cannot be decoded gets a local explanation naming the response that could not be
read.

## What is kept, and where?

The access token stays in memory and is never written down. Only the refresh token reaches
the Keychain, through `TokenStore` (`KeychainTokenStore` in a release build; see
[account-keychain.md](account-keychain.md)). A process that ends has nothing to leak but the
one credential it must keep. The profile is cached separately by `UserDefaultsProfileCache`;
see [entitlements.md](entitlements.md).

The server rotates the refresh token on every refresh, so the previous one is dead once a
new session arrives, and storing the new one is the session, not housekeeping. A Keychain
that refuses to store it fails the sign-in with `AccountError.sessionCouldNotBeKept`: an
account that appears, works, and is gone at the next launch is worse than a reported
failure.

## What happens when a refresh response is lost?

Each refresh carries an idempotency key (24 random bytes, base64url), and the key is reused
after a transport failure, because the server may have accepted the old token and lost only
the response. Within the server's retry window, the same old token and key answer with the
same rotated session rather than turning a dropped response into a sign-out. If that
ambiguous retry is answered `401`, the client keeps the credential and reports
`serverUnreachable` instead of clearing the session on an answer that might mean an expired
recovery window. The ambiguity is spent by one refused retry; the next `401` is definite.

Concurrent callers needing a token share one renewal in flight. A session generation counter
moves on whenever a session begins or ends, so a renewal that answers an older session is
dropped rather than adopted.

## When is a profile believed?

Only when its entitlement verifies against the Ed25519 key compiled into this build
(`Ed25519EntitlementVerifier.release`) and the entitlement names the same account as the
document carrying it (`Profile.isInternallyConsistent`). The check runs on a fresh sign-in as
well as on a cached copy read off the disk, so a profile that cannot be believed fails the
sign-in that produced it, where there is somebody to tell, rather than surfacing as a
mysterious sign-out on a later launch.

Profile reads are conditional: the cached copy's `ETag` goes out as `If-None-Match`, and a
`304` answers `ProfileRefresh.unchanged`. `AccountRefresh` applies the four answers
(`unchanged`, `updated`, `signedOut`, `noCredential`) to the cache; only `signedOut` clears
it.

## What does a `401` mean?

An access token rejected with `401` is usually one minted before a rotation. The service
renews once and retries; a second `401` after a fresh token means the session itself is
gone, and the Mac is signed out. If the credential vanished between the two requests,
another caller met a `401` first and cleared it, and that caller is the one entitled to act
on it; this one reports `noCredential` rather than deleting a cached profile on the strength
of a race.

## Why is the port bound before the browser opens?

Binding the loopback listener is the one step that fails for reasons nothing else in the
flow shares: SSH sessions, containers, security software that refuses any listener. Finding
that out after sending somebody to a sign-in page would leave a tab open with nowhere to
return to, so the port is bound first (an OS-chosen port on `127.0.0.1` only), and a Mac that
cannot bind one signs in by RFC 8628 device code instead: no port, URL scheme or
operating-system permission needed. `SignInChallenge.method` says which flow was chosen.

The browser flow uses PKCE (`S256`, a verifier from 32 random bytes) and a `state` from 24
random bytes. The listener is told the attempt's `state` when it binds. Anything else on this
Mac can reach a loopback port, so a request carrying another state, or none, is answered
with the failure page (`400`) and the port keeps waiting for the browser; only the matching
callback is answered as signed in and handed on. One attempt accepts at most
`connectionLimit` connections. Starting a new sign-in abandons any attempt still pending and
closes its port.

The device flow's verification address comes from the server and is handed to the system to
open, so anything but an `https` address with a host (`isOpenable`) refuses the sign-in
before it is opened.

While polling for device approval, `authorization_pending` is the ordinary answer rather than
a failure (RFC 8628 spells it as an error because a token endpoint has no other vocabulary),
and `slow_down` lengthens the interval by five seconds. The interval is at least one second,
and polling stops with a refusal once the code's lifetime has passed.

## How is the avatar fetched?

Quietly. The avatar path comes from the profile document but must be a plain absolute path
with no scheme, host, fragment or `.`/`..` segment, and the built address must have exactly
the API root's scheme, host and port, so a document from somewhere unexpected cannot send
the bearer token to another host. Every failure (a `404` for an account with no picture, a
`502` from a slow provider, an empty body) answers `nil`; none of them is worth a message to
somebody looking at their own initials.

## What does signing out do?

A person asking to be signed out is signed out whatever the network is doing. `signOut`
clears the Keychain token and the in-memory access token first, then asks the server to
revoke the refresh token and ignores the outcome. It never throws.

## Related

- [account-transport.md](account-transport.md): the socket underneath.
- [account-keychain.md](account-keychain.md): where the refresh token lives.
- [entitlements.md](entitlements.md): the signed profile and what it permits offline.
- [account-telemetry.md](account-telemetry.md): the other caller of the access token.
