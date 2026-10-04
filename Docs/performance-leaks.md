# Leaks

Two checks say whether Uttrflow's memory grows with use: the profile's leak check, which watches
the footprint across consecutive dictations (`LeakCheck` in `Sources/UttrflowEval/LeakCheck.swift`,
run by `uttrflow-bakeoff profile`), and the system's `leaks` tool on the running app and on the
suggestion model's reload path (`uttrflow-bakeoff reload-leaks`). The memory budget they protect is
in [`performance.md`](performance.md); the reasoning behind the leak rules is in
[`eval-methodology.md`](eval-methodology.md).

## The leak check

Ten consecutive medium dictations by default (`--dictations`), after one thrown away, footprint
read after each. One Debug run of thirty, re-wrapped into three columns:

```
Leak check — 30 consecutive dictations
  1  193.7 MB     11  156.9 MB     21  157.0 MB
  2  194.0 MB     12  156.9 MB     22  157.0 MB
  3  194.1 MB     13  157.0 MB     23  138.5 MB
  4  194.0 MB     14  156.9 MB     24  138.4 MB
  5  184.0 MB     15  156.9 MB     25  138.4 MB
  6  184.0 MB     16  156.9 MB     26  138.4 MB
  7  184.1 MB     17  156.9 MB     27  138.5 MB
  8  156.8 MB     18  156.9 MB     28  138.9 MB
  9  156.9 MB     19  156.9 MB     29  138.9 MB
  10 156.9 MB     20  157.0 MB     30  138.9 MB

  growth           -54.8 MB over 29 dictations (-1.9 MB each)
  never fell back  no
  allowance        33.6 MB
  verdict          CLEAN
```

Memory does not climb: it steps down three times as the allocator returns pages, ending 54.8 MB
below where it started. A ten-dictation run gave −34.4 MB.

The verdict is decided by `LeakCheck`, not by reading the column:

| verdict | rule |
|---|---|
| clean | total growth stayed inside the allowance, `defaultAllowanceBytes` (32 MiB, printed as 33.6 MB): about 3 MB a dictation over ten, a third of a gigabyte over a hundred |
| suspect | grew past the allowance but fell back at least once; only a longer run tells |
| leaking | grew past the allowance and never fell back |
| undetermined | fewer than three readings; two points are a line whatever they are |

## What `leaks` reports on the running app

`leaks $(pgrep -x Uttrflow)` on a Release build found four groups, none growing with time: the same
3,420 nodes and 583 KB at one minute and at 92 minutes.

| group | size | owner | state |
|---|---|---|---|
| `OnboardingFlow` cycle | 2.4 KB per onboarding controller | the app | fixed: `WindowLifetimeTests` fails on a cycle |
| `mlx::core::array::ArrayDesc` cycles | 0.4–1.7 MB, from loading the model | MLX | avoided on load and reload (below) |
| `NSXPCConnection` cycles (AppIntents daemon) | 4.7 KB | the system | not the app's |
| CoreAudio `ListenerBinding` / `ParameterListenerBinding` (148 nodes) | 9.5 KB | the app's cue engine | fixed size, by design |

**The cue engine's listener bindings.** `ShapedSoundPlayer.prewarm(_:)`
(`Sources/UttrflowAudio/RecordingCue+Engine.swift`) builds one `AVAudioEngine`, starts it once and
pauses it, and `pauseWhenIdle()` only pauses it between cues, so it lives as long as the process.
CoreAudio reports the bindings that engine registers as 148 leaks of 9,472 bytes; the count is the
same after prewarm and after eight cues and drops to zero when a rebuild tears the engine down, so
it is the engine being alive, not growth. The engine is kept because building it costs about
150 ms, which the next cue would otherwise wait for.

**The onboarding flow.** `OnboardingModel` reads its flow through `self` in `flow.onChange`, so the
flow does not hold a closure that holds the flow. The app builds one controller at launch to read
`isRequired` and another for each Sign In; a cycle there would keep each flow, network probe,
installer and model alive. `WindowLifetimeTests` draws every main-window page and Settings section
five times and checks that each window's model is released.

## The suggestion model's reloads

Quantising a model in MLX makes three sibling arrays (weights, scales, biases) that hold each
other. mlx-swift-lm's `loadWeights` then replaces them, still unevaluated, through
`model.update(parameters:)`, and MLX's array assignment skips the check in `~array` that breaks a
sibling cycle, so the three stay alive. It is CPU bookkeeping, not GPU buffers, paid on every
`loadWeights` — and the idle release reloads the suggestion model after every idle window
([`performance-suggestions.md`](performance-suggestions.md)), so it grew through a day of use.

**A reload never quantises.** `ReloadableWeights` builds the modules on the first load only. A
release keeps the modules and swaps every weight for an unevaluated `zeros` placeholder of the same
shape, which holds no buffer; a reload reads the safetensors, runs the model's `sanitize`, and
assigns them with `update(parameters:verify: .all)`, so every shape is still checked. Nothing on
that path makes a sibling array. A release waits for any pass still using the model, and a pass
stops its decode before it ends, so no step reads a weight that was swapped out.

**The first load does not quantise either.** `QuantizedLoad` creates the model from the same type
registry, reads the safetensors headers, and swaps each linear layer that the snapshot stores with
scales in a floating type, and that the configuration quantises, for a `QuantizedLinear` of
unevaluated zeros before `loadWeights` runs; any other layer is left to the library, so the
quantiser skips it and the stored weights replace the zeros with the same shape checks. It then
evaluates MLX's global random key, which every random initial weight split lazily into a chain of
siblings. Only the embedding still goes through the quantiser, because `QuantizedEmbedding` has no
initializer that takes arrays. The clean-up model loads through the same path.

`uttrflow-bakeoff reload-leaks` loads Gemma 3 4B, then releases and reloads it in one process,
running `leaks` on itself at 1, 5 and 20 reloads (`--checkpoints`). Release, 48 GB Apple silicon:

| | leaks | leaked bytes | median reload | footprint after the last release |
|---|---|---|---|---|
| library loader, quantising on every load (not used), first load | 12,181 | 2.35 MB | 5.8 s (first) | — |
| the same, 20 reloads | 144,034 | 27.14 MB | 4.96 s | 640 MB |
| `ReloadableWeights` alone, first load | 10,808 | 2.06 MB | — | 364 MB |
| `ReloadableWeights` alone, 5 reloads | 10,950 | 2.09 MB | — | 365 MB |
| with `QuantizedLoad` (shipped), first load | 75 | 14 KB | — | 339 MB |
| with `QuantizedLoad`, 5 reloads | 75 | 14 KB | — | 340 MB |

With quantising on every load, each reload added about 6,400–7,400 leaks and 1.2–1.4 MB, and the
footprint left after a release crept up with them. Without it the count stays where the first load
leaves it, a reload is about a second faster (3.75–3.93 s) because no module is built, and the same
fixed prompt gives the same answer after every reload. MLX's active memory after a release is
0 MB (`gpu-memory --release`).

Other ways round it are not used:

- **Evaluating the quantised arrays before they are replaced** would break the cycle, but
  `loadWeights` gives no moment between the two, and evaluating them would quantise the randomly
  initialised full-precision weights — gigabytes of work thrown away.
- **A loader option that skips the quantiser** does not exist: `LLMModelFactory` always passes the
  configuration's quantisation to `loadWeights`, and without it the stored `scales` fail
  verification, which is why `QuantizedLoad` builds the quantised layers itself.
- **Releasing less often** would only slow the growth, and would hold 3 GB longer on the small Macs
  the idle release exists for.
