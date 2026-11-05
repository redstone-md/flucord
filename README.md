# Flucord

A native Discord desktop client built with Flutter, without Electron or an
embedded browser. A [Redstone](https://redstone.md) project by **Rxflex**.

> [!IMPORTANT]
> Flucord is not affiliated with Discord. It uses Discord's private client
> protocol, which can change at any time, and a third-party client may break
> Discord's terms of service.

![Flucord: servers, channels, a conversation and the member list](docs/images/workspace-overview.png)

## Download

Windows x64 builds are on the
[releases page](https://github.com/redstone-md/flucord/releases): an
installer, a portable ZIP, and `SHA256SUMS.txt`.

Sign in with **Connections → Sign in with QR code** and scan the code with the
Discord mobile app. The session is kept in the Windows credential vault.

## What works

Chat, threads, forums and DMs; voice, video, screen share and calls; friends,
profiles and the member list; notifications, keybinds, Rich Presence and
themes. Windows is the tested platform.

Some parts are partial or not yet checked against the official client. See
[the feature parity table](docs/FEATURE_PARITY.md) for details.

## Build from source

Requires Flutter 3.44+, Visual Studio 2022 with the C++ desktop workload, and
the WebView2 Runtime.

```powershell
flutter pub get
flutter run -d windows
```

Add `--dart-define=FLUCORD_DEMO_MODE=true` to try the interface with demo data
and no account.

Before a pull request, run `flutter analyze`, `flutter test` and
`.\tool\audit_public_repository.ps1`. The next work is in
[roadmap.md](roadmap.md), and the docs are in [docs/](docs).

## License

Source-available under the [Flucord Project License 1.0](LICENSE): use, change
and distribute it with credit, published source and the same license. The
interface may not be reused outside Flucord or its forks. This is not an
OSI-approved open source license.
