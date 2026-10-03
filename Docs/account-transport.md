# The transport: why `URLSessionTransport` has no cache

`URLSessionTransport` (`Sources/UttrflowAccount/BackendTransport+URLSession.swift`) is the one
place the account module opens a socket. It puts a `BackendRequest` on the wire and hands back
a `BackendResponse`; every decision worth getting wrong (which path, which header, what body)
is in the request handed to it, built by `HTTPAuthenticationService` or `HTTPTelemetrySender`.
The `BackendTransport` protocol (`BackendTransport.swift`) is the seam tests replace. The
settings on its default session are load-bearing, and `URLSessionTransportTests` checks them
without a backend.

| Setting on `defaultSession()` | Value |
|---|---|
| configuration | `URLSessionConfiguration.ephemeral` |
| `urlCache` | `nil` |
| `requestCachePolicy` | `.reloadIgnoringLocalCacheData` |
| `timeoutIntervalForRequest` | 20 s |
| `waitsForConnectivity` | `false` |

## Why is there no cache?

`URLSession` does HTTP caching itself. Given a cached response it revalidates on its own, and
when the server answers `304` it does not tell the caller: it returns the cached body as a
`200`, which is correct behaviour for a browser and wrong here. The service sends its own
`If-None-Match` and needs to see the `304`, because that answer is what tells it the cached
profile is current. With a cache in the way every launch looks like a change: the profile is
rewritten every time, silently. Only a test against a real backend (`EndToEndTests`, enabled
by `UTTRFLOW_BACKEND_URL`) can see it.

## Why ephemeral?

A disk cache would write copies of the profile, which names the person and their plan, into a
cache directory nothing else in the app knows about or clears. A cookie store would keep state
for a service that authenticates with a bearer token and sets no cookies.

## Why twenty seconds, and no waiting for connectivity?

Twenty seconds survives a slow connection and is short enough that a first-run sign-in on a
dead network fails while the user is still watching. `waitsForConnectivity` is off for the
same reason.

## What counts as "no response"?

Every `URLSession` failure: no network, DNS, TLS, a timeout, a cancellation, and a response
that is not HTTP. None of them is the server saying no, and the transport throws
`BackendUnreachable` for all of them. Every answer the server gave, `401` and `502` included,
comes back as a `BackendResponse`. That difference decides whether this Mac keeps working
offline; see [account-session.md](account-session.md) for what the service does with it. A
thrown request may still have reached the server before the response disappeared, so
state-changing calls carry their own recovery semantics (the refresh idempotency key) rather
than treating a transport error as proof that nothing happened.

## Related

- [account-session.md](account-session.md): the service that builds the requests.
- [offline.md](offline.md): every network path in the app.
