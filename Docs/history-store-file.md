# The dictation history file, and the shape of the store around it

`DictationHistoryStore` in `Sources/UttrflowHistory/DictationHistoryStore.swift` holds
everything the user has dictated, on this Mac, between launches.

The history file is local working memory, not backup material. It is written through
`PrivateFile`, which marks the file and its Application Support folder `isExcludedFromBackup`, so
backup tools that honour Finder's exclusion flag should skip transcripts and their set-aside
copies. It is still an owner-only file on the Mac rather than an encrypted store; the at-rest
boundary is the user's login, FileVault and any encrypted backup volume.

## Its own file, not a key beside the settings

The history grows without bound, ages out on a clock, and is the one store whose contents
are the user's own words rather than their preferences. It lives at
`history.v1.json` under Application Support — versioned in the name so a shape too different
to read field by field can one day be introduced beside this one rather than on top of it.
Nothing else reads that file, so nothing else can be surprised by its size.

## An actor, not a `Mutex`-guarded box

`SampleAccumulator` takes a lock because its writer is CoreAudio's real-time thread, which
must never wait. Nothing here is real-time: the writer is a dictation that has already
finished, and the readers are a window and a menu. A lock would have to be held across a
file read and a whole-file rewrite, blocking whichever thread asked — and the thread that
asks most often is the main one. An actor turns that same waiting into a suspension, so the
caller's thread is free.

## Nothing is cached

The file is the single source of truth, and a copy beside it would be a second one: it would
disagree with a user who deleted the file in the Finder, and would have to be invalidated by
code that cannot see them do it. A read happens when a window is drawn, not per keystroke,
so re-reading is cheap enough to be worth the certainty.

`SnippetStore` is the same shape for the same reasons — see `Docs/ai-snippet-store.md`.

## Always keeps every record; finite retention has a cap

"Always" is the default transcript retention choice and promises to keep dictations until
the user deletes them. It skips the count cap on reads and every write, including flagging,
undoing a correction and deleting another record. The sentinel value lives in
`RetentionWindow.keepAlwaysDays`; settings and the history store share that value so the
storage rule agrees with the choice.

Finite retention keeps the newest thousand records within its window. The cap bounds the
whole-file rewrite on every dictation when the user has chosen automatic deletion. A capacity
passed in is clamped to zero, since a negative capacity would trap in `prefix`.

An Always history can grow beyond a thousand records, so reading and rewriting that file
cost more as it grows. A storage optimization must preserve those records rather than
silently imposing a deletion policy. Selecting a finite period applies its window and cap
to the existing history on the next read or write.

## Retention is applied on read as well as on write

The promise is about elapsed time, and time passes while the app sits idle. A user who
dictated once a fortnight ago and never again was still told the words would be deleted, so
`records(keeping:)` tidies the *disk* too. That rewrite is best-effort: refusing to answer
because the disk refused the tidying would punish the reader for something the reader cannot
fix, and either way nothing the user was told is gone comes back on screen.

What a read may hand back and what it may leave on the disk are two different lists, and they
differ for exactly one kind of record: one the window has passed on a clock too far ahead of it
to be believed. That record is hidden either way, and it stays on the disk until a clock that
has been put right sweeps it. `Docs/retention-clock.md` is why, and why a dictation stamped
ahead of the clock is treated as due rather than as young.

`changes(in:keeping:)` goes through the same call, so a correction belonging to a dictation
the user was told is gone cannot outlive it on the Corrections page. It answers with the
list and its completeness together because the two are read together, and two separate reads
could answer from two different files.

Order is arrival order — a new record is prepended, never sorted in. The clock belongs to
the caller, so a machine whose clock moved must not be able to shuffle what the user is
shown. The retention filter runs first and any finite-retention cap second. That cap is a plain
`prefix` because the list is newest-first throughout.

## Undo answers with a dictionary entry

`undoCorrection(_:keeping:)` returns the entry to blame for the change it put back. The
caller passes it to `PersonalDictionaryStore.recordRevert(of:)`, which is how a word the user
keeps rejecting retires itself; an undo that stopped at the history would cross out a row and
leave the bad word to be applied again tomorrow. `nil` means no dictation holds that change
or it is already undone — neither is an error, and neither writes anything, so undoing twice
cannot count twice against an entry.

## Reading and writing the file

Absent, unreadable, truncated, hand-edited, or written by a build that knew a different
shape — to a user those all mean the same thing, which is that the app should still open, so
`load()` answers with nothing. Salvaging record by record is not attempted: the store's own
writes are atomic, so the realistic corruption is a whole file somebody mangled, and half a
history restored is harder to explain than none. The unreadable file is renamed aside first
(`history.v1.json.unreadable-<seconds since 1970>`, by `LocalStore.read(_:from:)`), so the next
dictation starts a fresh file rather than writing over the only copy of the old one.

A set-aside copy holds transcripts, so it lives no longer than they would have. Every read
through `records(keeping:)` deletes a copy whose stamp is older than the retention promise, and a
promise of zero days deletes every copy. "Clear History" and "Reset personalisation" delete every
copy whatever its age, since nothing in the app can show one and nothing can tell it apart from
the transcripts the user just asked to be forgotten.

Writes are atomic, so a crash or a full disk cannot leave behind the truncated file `load()`
would then have to throw away. An empty list removes the file rather than writing `[]`, so an
emptied history leaves nothing of the user's on disk at all — which is what "Clear History"
says on the tin.
