# Benchmarks

Two tools, for two questions. The domain benchmark asks what one fold costs,
with no UI at all. The [profile scenarios](#profile-scenarios) ask what the
whole app costs, as frame times on Windows.

# Domain benchmark

This benchmark times the core `ChatWorkspace` folds: the work one gateway event
pays for on the chat path. It prints the median (p50) and the worst time (max)
of each fold at 1,000, 10,000, 100,000 and 300,000 held messages, always with
5000 channels and 20000 members.

It runs by hand and at release. CI does not run it, because times on a shared
runner are too noisy to fail a pull request on. `flutter analyze` does read it,
so a change to a fold's signature that breaks it shows up in CI.

## Run it

From the repo root, in any shell:

```
cd tool/bench; dart run.dart
```

This compiles the benchmark to native code and prints the table. It takes about
ten seconds. It needs only the Dart SDK. The Flutter SDK and `flutter pub get`
are not needed.

## Compare with an earlier result

Absolute times mean little across machines, so run both sides on one machine,
one straight after the other, with nothing heavy running.

1. Save the result of each side. `*.log` files are ignored by git.

   ```bash
   dart run.dart > new.log
   ```

   Windows PowerShell 5 writes UTF-16 with `>`, which git treats as binary, so
   use this there:

   ```powershell
   dart run.dart | Set-Content -Encoding ascii new.log
   ```

2. For the earlier side, check out the earlier commit in a second worktree and
   do the same there. Only compare commits with the same `domain_bench.dart`,
   since a different fixture gives different numbers. `git log domain_bench.dart`
   shows when it changed.

   ```bash
   git worktree add ../../../flucord-old <commit>
   cd ../../../flucord-old/tool/bench
   dart run.dart > old.log
   ```

3. Show the two results side by side, from `tool/bench`:

   ```bash
   git diff --no-index --word-diff ../../../flucord-old/tool/bench/old.log new.log
   ```

Read p50. Max is one run out of a few dozen, so it mostly shows what else the
machine was doing. Even p50 moves: over three runs in a row on a shared machine,
most rows stayed within 20%, and the worst row moved by 75%. Before you trust a
change, run both sides again and check that it stays.

## Baseline

`baseline.txt` holds results from past commits, newest first. The line above each
table says which commit and which machine. Its times only compare directly with
a run on that machine. On another machine, use it for the shape: how each fold
grows with the held messages. Add a table at release, and when a change moves
the numbers on purpose. Keep the old tables, so the file shows what changed.

## Why it is a package of its own

The app's dependency graph has packages with build hooks, such as `sqlite3`.
`dart compile` refuses a package whose dependencies have hooks, so this package
cannot depend on the app. It has no dependencies, and it imports the domain
files by relative path. This works because the files in `lib/src/domain` import
only `dart:` libraries and each other. It must stay that way, or this benchmark
stops compiling.

Run it from this folder. From the repo root, `dart` first tries to resolve the
whole app, which fails on a machine with no Flutter SDK.

# Profile scenarios

These run the whole app in profile mode, in a real session on a big made-up
account, and print the frame times of each scenario. Only the websocket and HTTP
are fake (the session harness in `test/support/session_harness.dart`). The account
and its traffic are test code (`integration_test/support/large_workspace.dart`),
and the same on each run. Production code has no measurement hook: the times come
from the engine's own `FrameTiming` reports.

| Scenario | What happens |
| --- | --- |
| scroll 500 messages | A mouse wheel turns steadily up a channel of 500 messages, loading older pages as it goes |
| switch channel | 20 clicks between two channels of 100 messages each |
| append in the active channel | 10 new messages a second for 20 seconds, with the reader at the end |
| 100 presences per second | Status changes of random members of any guild, for 20 seconds |
| 500 presences per second | The same, five times as fast |
| reconnect with 5000 channels | The socket drops, Discord refuses the resume, and a full READY and READY_SUPPLEMENTAL follow |

The account has 100 guilds, 5000 channels and 20000 members, like the domain
benchmark. Each scenario starts a fresh app. A stream always sends all its events,
so an app that cannot keep up takes longer than 20 seconds rather than doing less
work.

## Run it

On Windows, from the repo root:

```
flutter drive --profile -d windows --driver=test_driver/profile_scenarios.dart --target=integration_test/profile_scenarios_test.dart
```

This builds the app in profile mode, opens its window, and takes a few minutes
after the build. Leave the machine alone while it runs. It prints one table and
keeps the same numbers in `build/profile_scenarios.json`.

To run it with no Windows machine, start **Profile scenarios** by hand from the
repo's Actions tab. The job prints the table in its log and keeps the JSON file
as an artifact for 90 days. CI runs it at no other time.

## Read the result

All times are in milliseconds. Each scenario has three rows:

- `build`: the UI thread's work inside a frame.
- `raster`: the raster thread's work on that frame.
- `total`: from the vsync signal to the end of raster. This includes the time the
  frame waited for the UI thread, so a gateway event handled between frames shows
  here and not under `build`. Read this row first.

At 60 Hz a frame has 16.7 ms. Three things to keep in mind:

- **Read p95, p99 and max, not p50.** The test binding asks for a frame on every
  vsync, even with nothing to draw. A real app does not. So in a scenario with
  pauses, most frames are empty, and p50 shows the cost of an empty frame. Compare
  p50 only with the same scenario in another run.
- **Max is one frame.** For the reconnect, that frame is the point: it is how long
  the app froze. For the others, it mostly shows what else the machine was doing.
- **A GitHub runner has no GPU.** There, `raster` measures Windows' software
  renderer and says little about a real machine, and `total` carries that cost
  too. Runs of `build` compare well with each other, but a shared runner is noisy.
  For the real picture of `raster` and `total`, run it on a Windows machine with a
  GPU, and compare only runs on the same machine.

The load is a stress test, not a forecast. The spec names the presence rates. The
message rate is a busy channel, chosen here. `docs/LIVE_CAPTURE.md` measured about
0.3 presence updates a minute, on a small account that sent no guild subscriptions.
It says that is not a rate for a big account and must not size a budget. So nobody
knows yet how close these scenarios come to a real session.

Linux can run the scenarios, which proves that they work (use `-d linux`, under
`xvfb-run` with no display). Do not compare its times with anything. Software
rendering under Xvfb says nothing useful about frame times, and the first line of
the table names the platform so that such a run cannot pass for a Windows one.

## Baseline

There is no baseline yet. It needs a run on Windows, which has not happened. When
it does, put the table in `profile_baseline.txt` here, newest first, with a line
above it for the commit, and for the machine or the runner image.
