# Flucord

Flucord is an experimental native Discord desktop client built with Flutter.
It replaces the Electron shell with Flutter widgets, native Windows networking,
SQLite caching, platform integrations, and packaged media libraries. It does
not embed Discord in a browser or WebView.

> [!IMPORTANT]
> Flucord is not affiliated with Discord. The desktop-user transport relies on
> Discord's private client protocol, which can change without notice. Matching
> the official desktop profile does not guarantee protocol stability or account
> enforcement outcomes.

![Flucord workspace with servers, channels, messages, and members](docs/images/workspace-overview.png)

## Status

Windows is the primary verified target. macOS and Linux runners exist, but need
native-host release validation. The current desktop-user tracer bullet includes
native QR remote auth, vault-backed session restoration, Gateway workspace
hydration, channel history, and message operations.

The QR and main Gateway WebSocket handshakes are live-validated. A complete
mobile approval followed by live account, guild, channel, and history hydration
is still the release gate for roadmap item 69.

| Area | Status |
| --- | --- |
| Flutter desktop shell | Ready |
| Native QR login | Implemented; full approval validation pending |
| Saved account session | Ready; operating-system credential vault |
| Servers, channels, DMs | Implemented through Gateway bootstrap |
| Message history and mutations | Implemented through desktop REST |
| Live message events | Implemented through desktop Gateway |
| Threads, members, presence | Partial |
| Voice, video, screen share for user chat | Not ready |
| ETF/zstd Gateway framing | Not ready; JSON v9 currently used |

See [the full feature parity table](docs/FEATURE_PARITY.md) for exact boundaries.

## Screenshots

The screenshots use the deterministic local demo repository. No Discord account
or copied client data is involved.

| Workspace | Pinned messages |
| --- | --- |
| ![Server and channel workspace](docs/images/workspace-overview.png) | ![Pinned messages side panel](docs/images/pinned-messages.png) |

## Highlights

- Native server rail, channel tree, message timeline, member list, search, and
  responsive compact layouts.
- Replies, reactions, pins, threads, forums, polls, stickers, attachments,
  forwarding, editing, deletion, and unread boundaries.
- Native notifications, tray lifecycle, deep links, secure credential storage,
  SQLite cache, downloads, media playback, and voice-device surfaces.
- Separate transport adapters for desktop-user chat, OAuth, Bot development,
  and the optional Discord Social SDK.
- No Electron, Chromium runtime, browser session extraction, copied cookies, or
  imported Discord local storage.

## Quick Start

### Requirements

- Flutter 3.44 or newer with Windows desktop support.
- Dart 3.12 or newer.
- Visual Studio 2022 with the Desktop development with C++ workload.
- Windows 10 or 11 for the currently verified build.

### Run the client

```powershell
flutter pub get
flutter run -d windows
```

Open **Connections**, select **Sign in with QR code**, scan the QR code in the
Discord mobile app, and approve the desktop login. Flucord stores the resulting
session only in the operating-system credential vault.

### Run with mock data

```powershell
flutter run -d windows --dart-define=FLUCORD_DEMO_MODE=true
```

Demo mode is compile-time and never restores a real account session.

### Build a Windows release

```powershell
flutter build windows --release
```

Distribute the complete directory below, not only `flucord.exe`:

```text
build/windows/x64/runner/Release/
```

## Architecture

```text
Flutter presentation
  -> application controllers
    -> ChatRepository / gateway interfaces
      -> desktop-user, OAuth, Bot, or demo adapters
        -> WinHTTP WebSocket / REST / SQLite / OS vault / native media
```

Server state stays behind repository and gateway contracts. Controllers own
workflow state, widgets render immutable domain models, and transport secrets
do not enter presentation objects or logs. Windows WebSockets use WinHTTP via
Dart FFI because Discord's Cloudflare edge rejects the equivalent `dart:io`
TLS handshake before protocol negotiation.

Key entry points:

- `lib/src/domain/`: immutable models and transport-neutral contracts.
- `lib/src/data/discord/`: Discord REST, Gateway, remote-auth, and mapping code.
- `lib/src/application/`: connection, workspace, login, and media controllers.
- `lib/src/presentation/`: the native Flutter desktop interface.
- `windows/runner/`: Windows runner and optional native SDK bridges.

## Verification

```powershell
flutter analyze
flutter test
flutter build windows --release
```

Live network checks are opt-in:

```powershell
$env:FLUCORD_LIVE_REMOTE_AUTH_TEST='1'
flutter test test/discord_remote_auth_live_test.dart

$env:FLUCORD_LIVE_GATEWAY_TEST='1'
flutter test test/discord_desktop_gateway_live_test.dart
```

The current Windows checkout passes analysis, 493 automated tests, both live
WebSocket checks, and a release build. The live tests validate transport and QR
creation; they do not approve an account on the user's phone.

## Documentation

- [Feature parity](docs/FEATURE_PARITY.md)
- [Desktop protocol notes](docs/DISCORD_DESKTOP_PROTOCOL.md)
- [Session and transport boundaries](docs/SESSION_TRANSPORT.md)
- [Desktop integration](docs/DESKTOP_INTEGRATION.md)
- [Native media](docs/NATIVE_MEDIA.md)
- [Roadmap](roadmap.md)

## Contributing

Use `roadmap.md` as the source of truth for the next vertical slice. Keep
desktop-user, OAuth, Bot, Social SDK, and demo transports independent; add tests
at the repository/controller boundary; and keep Dart/C++ source files below 500
lines.

This repository does not currently publish a project-level license. Review that
before redistributing source or binaries.
