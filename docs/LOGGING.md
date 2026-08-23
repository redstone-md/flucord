# Logging

`AppLog` (`lib/src/app_log.dart`) is the app's diagnostic log. One call, three
mirrors: the log file, the console, and dart:developer (the DevTools log
view under `flutter run`).

## Where the file lives

`<application support>/logs/flucord.log`:

- Windows: `%APPDATA%\dev.flucord.app\flucord\logs\flucord.log`
- Linux: `~/.local/share/dev.flucord.app/flucord/logs/flucord.log`
- macOS: `~/Library/Application Support/dev.flucord.app/flucord/logs/flucord.log`

The app prints the resolved path as its first log line on every start. The
file rolls over to `flucord.log.1` past 2 MB; one previous file is kept.

Follow it live while running a built app:

```bash
tail -f "$APPDATA/dev.flucord.app/flucord/logs/flucord.log"
```

Or capture the console mirror instead: `flucord.exe > console.log 2>&1`.

## Record format

```text
2026-08-23 17:22:49.383 [W] desktop tray unavailable :: no icon
```

Timestamp, level letter (`I` info, `W` warning, `E` error), scope, message.
Warnings carry the error after `::`; error records also carry the stack
trace.

## Writing records

```dart
AppLog.info('voice', 'connected');                 // a state change
AppLog.warning('desktop', 'tray unavailable', error: error);  // handled failure
AppLog.error('connection', 'bootstrap failed',     // dead operation
    error: error, stackTrace: stackTrace);
```

The scope is the subsystem: `voice`, `golive`, `stream`, `desktop`,
`discord.gateway`, `connection`, and so on. Most modules already funnel
their diagnostics through one private `_diagnose` helper; add the line
there, not at every call site.

The log never throws: a broken file sink disables itself and records keep
reaching the console.

## What is captured without wiring anything

`main.dart` routes uncaught errors from Flutter, the platform dispatcher,
and the app's zone into `AppLog` under the `app` scope. A crash or an
unhandled async error always leaves a record, even in a built release app.
