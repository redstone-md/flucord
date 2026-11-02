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
