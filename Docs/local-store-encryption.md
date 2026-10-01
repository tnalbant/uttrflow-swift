# Encrypting local user stores

## Status

This page records the scheme chosen for issue #3152. It is a design decision, not an
implementation claim: the stores on `main` remain plaintext JSON, SQLite, image and WAV
files, protected by owner-only permissions and backup exclusions. Store changes follow as
separate work; this page is their shared contract.

## Decision

Use CryptoKit `AES.GCM` with a 256-bit random symmetric key. Generate a fresh 96-bit nonce
for every file write, and authenticate the file's stable logical filename as additional
data. AES-GCM provides confidentiality and authentication; a wrong key, changed filename
or modified ciphertext must fail to open. CryptoKit creates a random nonce when sealing
without an explicit nonce and authenticates the additional data on both seal and open
([`AES.GCM`](https://developer.apple.com/documentation/cryptokit/aes/gcm),
[`AES.GCM.SealedBox`](https://developer.apple.com/documentation/cryptokit/aes/gcm/sealedbox)).

Store the key as a non-synchronizable generic-password item in the macOS Keychain, under a
stable, versioned Uttrflow service name and the current Unix user as account. Use
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: the key is unavailable after a restart
until the user unlocks once, then remains available to background work for that session;
it does not migrate to another Mac in a backup
([Apple Keychain accessibility](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)).
That supports launch-at-login and background capture while keeping a copied store folder
from being useful on another Mac. A restored or replacement Mac starts with an empty local
store unless the matching key is deliberately transferred through a future, separately
reviewed recovery flow.

The service identity must remain stable across product upgrades. Do not key it by a build
hash: losing the item would make existing ciphertext unreadable. Development builds and
tests must use an injected key provider or isolated test service; a keychain error must not
fall back to plaintext or to a newly generated key for an encrypted file. Before rollout,
exercise the signed release and ad-hoc development paths because their Keychain access
requirements differ; a build that cannot retrieve the stable item must fail closed.

## File envelope

Every encrypted file starts with this byte sequence:

| Part | Size | Meaning |
|---|---:|---|
| Magic | 8 bytes | `UTTFLOWE` |
| Version | 1 byte | `1` |
| Nonce | 12 bytes | Fresh AES-GCM nonce for this write |
| Ciphertext | Variable | Encrypted file payload |
| Tag | 16 bytes | AES-GCM authentication tag |

The complete envelope is authenticated with the UTF-8 bytes of the file's stable logical
filename, such as `history.v1.json`, as AAD. Bind the logical filename rather than the
absolute path so a store can move with its Application Support folder, while swapping two
store files still fails authentication. Keep the existing JSON encoding as the plaintext
payload; the envelope is the only on-disk wrapper.

JSON stores seal the complete encoded file on every write through the `PrivateFile` seam.
The writer continues to use its atomic replacement, owner-only mode and backup exclusion,
but writes only the envelope. SQLite, pictures and recordings do not go through that JSON
seam and need their own changes under issues #3153, #3154 and #3156.

## Reading, migration and failure

The store reader checks the magic before decoding. A matching magic must have a supported
version, enough bytes for the nonce and tag, and a valid authentication tag before any
plaintext is returned. Unknown versions, truncated envelopes, wrong keys and modified
data are unreadable stores, never empty stores.

For a legacy JSON file without the magic, decode the old shape first. Only after decoding
succeeds, retrieve or create the installation key, seal the same payload and atomically
replace the plaintext file. If reading, key access or writing fails, preserve the original
file and refuse the write; never replace the only readable copy with an empty default.
Creation of a new key is allowed for a genuinely new store or a successfully decoded
legacy file. It is never allowed as a response to a missing key for an encrypted envelope.

An encrypted file whose Keychain item is definitely missing is quarantined with
`StoredList.setAside`; the store reports it as unavailable and refuses writes. Do not
create a replacement key while set-aside encrypted files remain, since that would turn a
missing-key failure into silent data loss. A key that is temporarily unavailable, such as
while the Keychain is locked, leaves the file at its original path and the store read-only;
do not quarantine it because the key may become available after the next unlock. A
malformed or unauthenticated envelope is also quarantined with `StoredList.setAside`. If
quarantine fails, refuse all writes so the original bytes cannot be replaced. In no case
may a read pretend the store is empty.

## Deletion and limits

This scheme encrypts each store file under one installation key. Deleting a record rewrites
or unlinks ciphertext; it is not per-record cryptographic erasure. Resetting all local
personalisation must delete the Keychain item as part of the same reported operation, so
retained copies of encrypted files cannot be opened by a fresh key. If Keychain deletion
fails, reset must report failure rather than claim the data is revoked.

Atomic replacement and unlink do not reliably overwrite old APFS or flash-storage blocks.
This scheme leaves those old blocks as ciphertext, but while the same Keychain key exists
they are not cryptographically revoked. It cannot remove plaintext already present in old
backups, snapshots or copies made before migration. FileVault, owner-only permissions and
backup exclusions remain useful layers and are not replaced by this design.

Encryption protects files copied away from the Mac and data at rest. It does not protect
plaintext in memory while Uttrflow is using it, or an active user session from a process
that can obtain the Keychain key. The user must unlock once after restart before encrypted
stores are available to background work.

## Required tests and rollout

The shared crypto layer needs an injected in-memory key provider and tests for round-trip,
wrong key, wrong filename AAD, modified and truncated envelopes, unknown versions, and
missing-key refusal without overwriting. Migration tests must prove that valid legacy JSON
is replaced by an envelope, while malformed JSON and failed writes preserve the source.
Store-level tests must show that a Keychain failure is visible and does not produce an
empty successful read.

Roll the envelope into `PrivateFile` and `StoredList` first, while retaining the legacy
reader for one-time migration. Handle SQLite and its `-wal`/`-shm` files separately in
#3153; clipboard pictures in #3154; history, dictionary and snippets in #3155; raw audio
recordings in #3156; and reset/deletion behavior in #3157. Do not update user-facing docs
to say those stores are encrypted until their implementation and migration have shipped.
