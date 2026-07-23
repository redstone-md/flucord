# Flucord

Flucord is a native Flutter desktop messaging client. The current Windows
tracer bullet uses a deterministic in-memory transport to prove navigation,
message history, search, composition, member presence, and theme switching
without a browser runtime.

## Run

```powershell
flutter pub get
flutter run -d windows
```

## Verify

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build windows --release
```

## Structure

- `lib/src/domain`: immutable entities and the transport contract.
- `lib/src/data`: transport implementations.
- `lib/src/application`: isolated remote and local state controllers.
- `lib/src/presentation`: adaptive desktop workspace and focused widgets.
- `lib/src/theme`: shared surface, semantic color, and typography system.

See `roadmap.md` for the staged path from this local tracer bullet to a
production transport, platform integration, and voice.
