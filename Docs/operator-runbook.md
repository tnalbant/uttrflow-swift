# Operator runbook

What an operator configures, rather than develops, for this repository's tooling: the
entitlement key the app trusts, the accuracy recordings, notarisation, and the provider marks.
Each is independent, and the app builds and runs locally without any of them: an app built
without the backend address and key falls back to the in-process development backend
(`OnboardingAccountLayer.forThisBuild()`, see `Docs/development-build.md`), and every other
item here only gates a measurement or a distribution step.

## The entitlement key

`Ed25519EntitlementVerifier.releasePublicKeyBase64` in
`Sources/UttrflowAccount/EntitlementSignature.swift` holds the account backend's entitlement
public key, base64; `releasePublicKeyBytes` decodes it and `isConfigured` is true when it is a
key. `ReleaseVerifierTests` holds it to 32 bytes that refuse anything the backend did not sign.

**Rotating the backend's signing key is release-blocking.** Generate the new pair on the backend
side, replace `releasePublicKeyBase64` with the new public half, and ship both together: an app
built against the old key rejects every entitlement a rotated backend signs, failing closed.
The backend address is the other half of the pair; `Docs/releasing.md`, "Pointing a build at
the backend", has why both or neither.

**Never fill the key with zeroes.** An all-zero Ed25519 key is a small-order point that
CryptoKit verifies without the cofactor, so it accepts a blank all-zero signature for about one
message in four (491 of 2,000 when measured). Anyone could grant themselves Pro.
`ReleaseVerifierTests.rejectsTheDegenerateKeyThatWouldAcceptAForgery` asserts the trap over 64
forgeries and that the release key is not all zeroes, so nobody "fixes" the constant that way.
`Docs/entitlements.md` has the signed payload.

## Accuracy recordings

Blocks any accuracy number, and therefore the correction feature's regression gate. Nothing
else: the evaluation harness, `UttrflowEval`, is never linked into the app, and `bundle.sh`
check 10 refuses a build that carries it.

Two jobs need recordings, and they need different amounts. **A regression check** needs one
voice reading the same 18 passages before and after a change, about 14.7 minutes of reading;
[`measuring-accuracy.md`](measuring-accuracy.md) is that procedure. **An accuracy number** for
people in general needs many voices and rooms, recorded in sittings with `uttrflow-eval`:

```bash
uttrflow-eval record --backend <url> --cohort <reader>-quiet --upload
```

`--backend` has no default, so the tool cannot point at production by accident, and the
operator token comes from `UTTRFLOW_OPERATOR_TOKEN` (or `--operator-token`) so it stays out of
shell history. The cohort and every passage's upload name are validated before anything is
recorded: two to sixty-four lowercase letters, digits and hyphens. Recording is resumable,
and **the local write is the commit**: a take is saved to disk before it is offered to the
backend, so a crash or a dropped connection costs an upload, never a take. Uploads still owed
at the end of a sitting are sent on their own, recording nothing new:

```bash
uttrflow-eval record --backend <url> --sync
```

Then measure against the backend's catalogue. `--from-catalogue` measures only samples cached
on this Mac and refuses when any are missing, so pull first:

```bash
uttrflow-eval pull --backend <url>
uttrflow-eval transcribe --from-catalogue --backend <url> --baseline ./baseline.json --save-baseline
```

Results are never pooled into one number: each sample is kept with its language, stresses and
cohort (`AccuracyBaseline`), and any slice going backwards counts as a regression even when the
headline improves. `Docs/eval-methodology.md` has the scoring.

## Notarisation

Blocks giving the app to anyone else. Running it yourself is not blocked.

Needs an Apple Developer Program membership and a Developer ID Application certificate. Store
the notarytool keychain profile once (`Docs/packaging.md`, "Notarisation credentials"), then:

```bash
make app-dist IDENTITY="Developer ID Application: NAME (TEAMID)"
make notarise
```

`make notarise-check` runs every preflight with no account. `Docs/releasing.md` has the full
release order.

## Provider marks

Fetched, never committed: they are other companies' trademarks and this repository is public.

```bash
./Scripts/fetch-provider-marks.sh
```

That places Google's four-colour G at `Sources/Uttrflow/Resources/GoogleG.png`, which
`.gitignore` keeps out of the repository; `make app` and `make app-dist` run it first.
Shipping the mark inside an app that implements Google Sign-In is what Google publishes it
for; redistributing it in public source is a different act. Marks are never redrawn, so a
build without the file shows a generic person symbol in the mark's place
(`OnboardingProviderMark`), and Apple's mark is the system `apple.logo` symbol. The script does
not fetch GitHub's mark; only Google is offered as a sign-in provider
(`SignInProvider.offered`). `bundle.sh` needs no change for the mark: the target's resources are
already sealed into `Contents/Resources`.
