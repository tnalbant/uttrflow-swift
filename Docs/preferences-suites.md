# Temporary `UserDefaults` suites in tests

A few tests must touch real preferences: the adapters over `UserDefaults`
(`SystemUserDefaults`, `SystemDefaultsStorage`) claim only that bytes go in and come back, and
nothing short of a real domain notices if that stops being true. Those tests use
`withTemporaryDefaultsSuite` from `Sources/UttrflowTestSupport/TemporaryDefaultsSuite.swift`,
which hands the closure a fresh domain named `com.uttrflow.tests.<UUID>` and removes it
afterwards. Removing a domain so that no file is left behind is harder than it looks, and this
page is why the helper has the shape it has.

## `cfprefsd` owns the file, not the test

Emptying a domain does not remove it. `cfprefsd` writes `~/Library/Preferences/<suite>.plist`
on the first write and **writes the domain back after the owning process exits**. A test can
empty the domain, delete the file, see `fileExists` return `false` and pass, and the plist is
back on disk twenty to thirty seconds after the run finished. Without a working cleanup, every
run of the suite, on every machine and CI runner, leaves one empty 42-byte plist per test.

Each cleanup was measured by creating suites, running the cleanup, and checking for the file
thirty seconds *after* the process exited:

| cleanup | file gone after exit? |
| --- | --- |
| `removePersistentDomain(forName:)` alone | no |
| `removeSuite(named:)` as well | no |
| `CFPreferencesSynchronize` as well | no |
| delete the plist from inside the process | no, it returns |
| `/usr/bin/defaults delete`, then delete the plist | yes |

Nothing in-process dislodges the daemon's copy, because the registration being flushed belongs
to *this* process. Asking from another process is what works, so `remove()` empties the domain,
flushes this process's pending write with `synchronize()`, drops the suite, runs
`/usr/bin/defaults delete <suite>` as a subprocess, and then deletes the file.

## The sweep makes it self-healing

Even with the subprocess the race is only mostly won: from an empty `~/Library/Preferences`
baseline, roughly one run in three to one in eight still leaves two files behind. No
in-process cleanup can be airtight, because the write happens after the process is gone.

So the helper does not rely on winning. A suite from `withTemporaryDefaultsSuite` lives for the
milliseconds of one closure, which means **any file with the prefix that is older than a few
minutes was abandoned by a run that has finished**. Once per test process,
`TemporaryDefaultsSuite.sweepStaleSuites(olderThan:)` removes those, through the same
`defaults delete` and file removal. A later run clears what an earlier one left, and the count
cannot grow without bound.

| Constant | Value | Why |
| --- | --- | --- |
| `TemporaryDefaultsSuite.namePrefix` | `com.uttrflow.tests.` | How a later run recognises a suite this helper made. |
| `sweepStaleSuites(olderThan:)` default | 600 seconds | A suite in use is seconds old, so two checkouts running tests at once never sweep each other's. |

Measured over fourteen consecutive test runs without clearing between them: 0 files for rounds
1–4, 2 files at round 5 (the race lost), 2 held through round 13 while under the cutoff, and 0
at round 14 as the sweep reclaimed them. Peak 2, ending at 0.

The order inside `remove()`, flushing this process's pending write before the handover,
measured 0 leaking rounds of 8 against 1 of 8 for the other order. At a one-in-eight rate a
change that does nothing shows 0/8 about a third of the time, so that is not proof; the order is
kept because flushing before the handover is correct on its own terms.

## Measuring this without fooling yourself

**Count from zero.** Against a directory already holding hundreds of abandoned files, a delta
of two is invisible. Drain to zero first, and drain twice: a writeback still in flight from an
earlier run lands in the next run's window and is easily blamed on it.

**Do not instrument the cleanup.** File I/O added to `remove()` to log what it did shifts the
timing enough to hide the race: sixteen consecutive rounds came back clean that way while an
uninstrumented run leaked. Use per-suite marker files or an observer outside the process instead
of writing from inside the path being timed.
