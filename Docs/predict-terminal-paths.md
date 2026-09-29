# Tab-to-complete in a terminal: only what exists from here

A suggestion in a terminal is a command somebody may run with one key. A `cd` into a directory
that is gone, a `cat` of a file in another project, a `git checkout` of a branch this repository
never had: each costs more than no suggestion at all. So before a terminal line is drawn, from
the corpus or from the model, `TerminalLineCheck` reads the whole line the way the shell would and
asks the disk whether everything it names is there. False negatives are accepted; a wrong path is
not.

## Where it runs

`Verifier.admits` runs first in both paths to the screen:

- `Verifier.verified`, for remembered lines and the machine's own candidates, before any verdict.
- `Verifier.standing`, for every line the model wrote and the alternatives built from the
  machine's values in `SuggestionCoordinator.generate`.

A line refused here is simply not drawn. It is not superseded in the corpus, because a directory
that is missing today may exist tomorrow.

Two rules decide what runs where:

1. **A destructive line is never offered, in any field.** `DestructiveCommand.matches` reads the
   same parsed commands as the terminal path check and is asked of every line, whatever its evidence.
   Unresolved shell syntax is refused in terminals; ordinary editor prose is not parsed as a terminal
   command. The same test already keeps destructive lines out of the corpus
   (`CaptureGate`), so this only closes the lines the model writes and those remembered before the
   capture gate existed.
2. **The path check runs only in a terminal**, meaning an application `TerminalApplications`
   names. An editor's document also has a directory for a scope, but its lines are prose, and a
   shell grammar would refuse all of them.

## What the check reads

`ShellWords` splits the line into simple commands, with quotes and backslashes undone, `~` and
`$HOME` expanded, and redirections set aside (a file read with `<` is kept and checked). A word the
shell would still rewrite — a glob, any other variable, `~name` — is marked unresolved. A line
with a subshell, a command or process substitution, a here-document or unbalanced quoting is
refused whole, since only running it could say what it names.

Then, per simple command, after leading assignments and wrappers (`sudo`, `env`, `nice`, `time`,
`command`, …) are read past:

| What | Must be |
|---|---|
| the command word | a builtin, an alias from the shell's configuration, or an executable file on the search path; a word with a slash, an executable file at that path |
| `cd`, `pushd` | one directory; with none, home; `cd -` and the directory stack are allowed but lose track of where the line is |
| `cat`, `less`, `head`, `tail`, `bat`, `wc`, `source`, `.` | every operand a file |
| `ls`, `du`, `tree`, `stat`, `file`, `diff`, `open`, `rm`, `rmdir`, the editors | every operand a file or a directory |
| `cp`, `mv` | every source; the destination may be new |
| `chmod`, `chown`, `chgrp` | every operand after the mode |
| `python3`, `node`, `ruby`, `sh`, … | the script, when no flag comes first |
| `grep`, `rg`, … | every operand after the pattern; a file named by `-f` or `--file` must exist as a file |
| `git checkout` | a branch, tag, remote branch or `HEAD` relative that the refs hold, or paths that exist; a new branch's start point |
| `git switch` | a local branch, or a remote branch of that name; with `-c` or `--detach`, a commit the refs hold |
| `git add`, `restore`, `rm`, `mv` | paths that exist |

Any other command's arguments are not judged. A trailing slash asks for a directory. Flags that
take a value (`head -n 5`, `open -a Safari`) have the value skipped, not checked.

**The working directory.** The terminal's directory is `Surface.scope`, which comes from the
field's `AXDocument` and otherwise from the window title. It is believed only when it is an absolute
path, or one from `~`, that names a directory that exists; otherwise it is unknown, and every
relative path is refused while absolute and `~` paths are still checked. A `cd` in the line moves
the directory for the commands after it when they surely follow it (`&&`, `;`); after `||`, `|` or
`&` the directory is unknown. `..` is folded lexically, as `cd` does.

**Branches.** `GitRepository` finds `.git` by walking up from the directory, follows a worktree's
`gitdir:` and `commondir`, and looks a ref up as a loose file under `refs/` or a line of
`packed-refs`. A repository whose refs live in a reftable, or whose `packed-refs` is over 8 MB, is
not read, and its branch lines are refused. A commit hash is refused too, since telling one from a
typo means reading the object store.

## A session on another machine

After `ssh`, the shell that prints the prompt is not on this Mac. Its `AXDocument` is not updated,
so the terminal goes on publishing the directory the session started in, and everything that reads
`Surface.scope` then describes this disk while the line runs on another: the check above stats the
remote command's paths here, the machine index offers local files, branches and programs, and the
lines are remembered under the local directory's corpus.

So a terminal in a remote session is scoped as that session — `RemoteSession.scope`, which is
neither a path nor a host — rather than as a directory. Three things follow from the one change:
`EnvironmentSource.workingDirectory` finds no directory, so nothing here is listed or offered;
`Verifier.admits` refuses every line in that surface, because no question put to this disk could
stand behind one; and what is typed there is remembered under the session rather than under the
directory this Mac was left in. Nothing is stat'ed on the strength of a remote prompt.

**How the session is recognised, and how reliable that is.** Whether a terminal is remote is not
knowable from outside it, so this reads the one signal the app already holds: the window title,
which by default carries the name of the foreground process — `ssh`, `mosh`, `mosh-client` — as
its own word. A word that only reads like one is not it: `~/.ssh`, `.ssh`, `ssh-keygen` and `scp`
keep the directory.

The two other candidate signals were weighed and left alone:

- **A `user@host` prompt or title that differs from this Mac's name.** It needs this Mac's names to
  compare against, and it has several — the Bonjour name, the local hostname with and without
  `.local`, the name the network hands out — so a local prompt reads as remote often enough to
  lose the feature in ordinary local terminals. That is failing closed in the wrong place.
- **A process check.** What a terminal is running is the terminal's child, not this app's, and
  reading it means looking outside what the app is permitted to see. It is not worth a wider
  permission.

**This detection fails open**, and deliberately: with no positive signal a terminal is read as
local, so an `ssh` session whose title names no program — one the remote shell has overwritten,
or a terminal configured not to show the process — is still read against this disk. Failing the
other way means treating every terminal as possibly remote, which withdraws the feature from every
local one. So this narrows the bug to the case where no signal exists rather than closing it; a
session that announces itself is handled, and one that does not is where it stood before.

## tmux and screen panes

A tmux or GNU screen client presents its panes inside one terminal window and one Accessibility
text area. The document directory exposed there belongs to the outer terminal process; it does not
identify the pane currently under the caret. Pane switches therefore cannot safely reuse that
directory for path checks, branch lookups, machine candidates, or corpus identity.

When the terminal window title identifies `tmux` or `screen` as the foreground program, the field is scoped
as `RemoteSession.scope`. The verifier consequently refuses terminal lines, no local directory
index is queried, and observations are kept under an opaque session scope rather than the outer
directory. This is deliberately fail-closed because a wrong pane's filesystem can make an unsafe
command appear valid.

The title is the only pane-related signal this process can obtain without entering the shell or
requesting broader access. Detection is best-effort: if a terminal configuration hides the
multiplexer name from its window title, Accessibility still cannot reveal the active pane's cwd,
and the outer document may be treated as local. The same limitation applies to multiplexers whose
title format omits their name. Users who need reliable per-pane suggestions should configure their
terminal title to include `tmux` or `screen`, or use a non-multiplexed terminal window.

## What it never does

It never runs a program. Everything it knows comes through `FileSystemProbing`: a `stat`, an
`access(X_OK)`, a bounded read and a bounded listing. The test double records every question, and
the tests hold that a line the check refuses reaches the machine index only for the shell's
aliases, which are read from its configuration as text. The machine index's branch list is read
from the same refs, so no `git` process is started for branches either. A line the check lets
through still goes on to the verdicts in `Verifier`, whose verb lookups are the machine index's
own (see `predict-agent.md`, A2).

It never lists a directory to check a path; a path is one `stat`. The only listing is
`refs/remotes`, which holds a handful of names.

## Cost

Measured on an Apple silicon Mac under heavy load (load average above 20), on a directory of
10,000 entries (9,000 files and 1,000 directories), seven lines per turn:

| | Per turn |
|---|---|
| `TerminalLineCheck`, uncached | 0.29 ms |
| the same through `CachedFileSystem` | 0.13 ms |
| `git checkout main` from inside a worktree, uncached | 0.10 ms |
| for comparison, the machine index listing that directory's files | 29 ms |
| and its directories, one `stat` per entry | 41 ms |

`CachedFileSystem` believes a stat or a small read for two seconds. A path on `/Volumes`,
`/Network` or `/net` is stat'ed on a queue of its own and waited for 20 ms; a volume that misses the
deadline is answered `unknown`, which refuses the line, and is left alone for 30 seconds.

## Fixtures

`uttrflow-bakeoff complete --fixtures --only terminal`, Release, Gemma 3 4B from disk, 256 cuts.
`Grounding` stands each fixture on a `FixtureDisk` built from its machine.

| | Hit | Precision (wrong shown) | Coverage | p50 |
|---|---|---|---|---|
| before the check | 247 | 96.77 % (8) | 96.88 % | 166 ms |
| with the check | 239 | 97.07 % (7) | 93.36 % | 136 ms |

Every one of the eight hits lost was a first line the check refuses because running it would fail
or harm: `cat docs`, `tail logs`, `tail -f logs`, `cat ~/Desktop` and `node public` stop at a
directory where a file is needed; `cd ~Projects` names a user's home that is not there;
`cat projects/api/README.md` names a file the fixture's disk does not hold; and
`kubectl delete api` is destructive. The catalogue counts a line ending on a whole word of the
right answer as a hit, which is why they counted before.

## Limits, each a false negative or an open question

- A shell function, a `CDPATH` entry, or a program installed somewhere the search path does not
  name (the launch `PATH`, `/etc/paths`, `/etc/paths.d` and the usual install directories) is
  refused.
- A glob or a variable in a checked position refuses the line, even where it would match.
- A remote session whose window title names no remote program is read as local, and a local
  directory named `ssh` or `mosh` is read as a remote session and offered nothing.
