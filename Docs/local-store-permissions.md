# Who may read the local store

Everything Uttrflow keeps about a person is under `~/Library/Application Support/Uttrflow/`
(`LocalStore.folder`; a development build with a longer bundle identifier writes under
`Uttrflow.<suffix>` instead): the clipboard and the pictures in it, the dictation history, the
personal dictionary, the snippets, the suggestion corpus and the recordings waiting for a retry.
None of it is sent anywhere. Its protection on disk is two layers: the file modes on this page,
and the encryption in [local-store-encryption.md](local-store-encryption.md).

`PrivateFile` in `Sources/UttrflowCore/Support/PrivateFile.swift` is the one place that creates
those folders and writes those files, owner only, and `make store-permissions` checks that
nothing in `Sources/` goes around it.

| Constant | Value | Applies to |
|---|---|---|
| `PrivateFile.directoryMode` | `0700` | Every folder `PrivateFile.makeDirectory(at:)` creates |
| `PrivateFile.fileMode` | `0600` | Every file `PrivateFile.write(_:to:)` creates |

## Why a helper rather than a convention

Foundation writes under the process umask. On a Mac that is `022`, so `data.write(to:)` lands
at `0644` and `createDirectory` at `0755`: readable by every user on the Mac, with nothing at
the call site to suggest it.

What keeps a reader out of such files by default is one property of the platform:
`~/Library` and `~/Library/Application Support` are `0700`, so loose modes inside them are not
reachable. That stops holding the moment the files are copied somewhere that keeps their own
modes (a migration, a `tar` or `rsync` of the folder, an external disk, a backup restored
elsewhere) or on a Mac where somebody has loosened the folders above.

## What the helper does

| Call | Behaviour |
|---|---|
| `makeDirectory(at:)` | Creates the folder and its parents at `0700`, then tightens the folder again and marks it excluded from backup. `createDirectory` applies its attributes only to folders it creates, so tightening afterwards is what fixes a folder that already existed. |
| `write(_:to:)` | Makes the folder, writes atomically, marks the file excluded from backup, then sets its mode: `0600` for a new file, or the previous file's owner bits for a replaced one. |
| `tighten(at:)` | Takes group and other off a file this app did not write itself; used on the suggestion corpus's SQLite files when the corpus runs without encryption. |
| `excludeFromBackup(at:)` | Sets `isExcludedFromBackup`, which backup tools that honour Finder's exclusion flag skip. Also applied to a file set aside as unreadable (`LocalStore.setAside`). |

`write` sets the mode after the write because an atomic write does not rewrite the file: it
writes a temporary file beside it and renames it, so a mode set before the write belongs to a
file that is already gone, and the replacement carries the umask's mode. For the same reason
`write` reads the old file's owner bits *before* the write and puts them back on the
replacement; reading them afterwards would quietly restore write permission to a file somebody
had made read-only.

All of them tighten by taking group and other away and leaving the owner's own bits as they
are. That is the difference between "nobody else may read this" and "this is `0700`", and only
the first is the app's business: somebody who made the folder read-only meant it, and a helper
that set `0700` unconditionally would hand write permission back on the next save.

## The window this leaves

Between the rename and the mode being set, a freshly created file has whatever mode the umask
gave it. The folder around it is already `0700` by then, so no other user on the Mac can reach
it; the window is in the file's own mode, not in its reachability. Closing it would mean giving
up the atomic replace, and a file the user can lose is worse than a file that is briefly `0644`
inside a folder nobody else may enter.

## Keeping it true: `make store-permissions`

`Scripts/store_permissions_audit.py` runs as `make store-permissions` and as part of
`make verify`. It needs no build. It scans every `.swift` file under `Sources/`, skipping lines
that start with `//`, for four calls:

| Pattern | Reported as |
|---|---|
| `createDirectory(` | `createDirectory` |
| `createFile(atPath:` | `createFile` |
| `.write(to:` or `.write(toFile:` | `write(to:)` |
| `O_CREAT` | `open(O_CREAT)` |

Any match outside the allowed paths fails the run. Each allowed path states its reason in the
script and prints it on every run, and names the calls it is excused; a file excused one call is
still held to the rest.

| Path | Excused | Why |
|---|---|---|
| `Sources/UttrflowCore/Support/PrivateFile.swift` | every call | The helper itself. |
| `Sources/UttrflowEval/`, `Sources/uttrflow-bakeoff/`, `Sources/uttrflow-dev/`, `Sources/uttrflow-eval/` | every call | The evaluation harness and developer tools, which never ship and write no user data. |
| `Sources/UttrflowTestSupport/` | every call | Golden fixtures beside tests; this support module is never linked into the app and does not write user data. |
| `Sources/UttrflowSpeech/SpeechModelStore.swift`, `Sources/UttrflowSpeech/TokenizerDownload.swift` | every call | Downloaded model weights and tokenizer files, which are public. |
| `Sources/UttrflowCore/Support/SingleInstanceLock.swift` | `open(O_CREAT)` | Opens its lock file `0600` and needs the descriptor to `flock` it. |
| `Sources/UttrflowAudio/RecordingWriter.swift` | `open(O_CREAT)` | Opens each recording `0600` and writes through the descriptor. |

A new path that writes for itself either goes through `PrivateFile` or is added to the script's
`ALLOWED` table with its reason. The audit exists because the fix is mechanical and the coverage
is not: a new store reaches for `data.write(to:)` naturally, and nothing about that line looks
wrong.
