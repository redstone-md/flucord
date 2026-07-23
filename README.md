# Flucord

Flucord is a native Flutter desktop messaging client. The current Windows
tracer bullet uses a deterministic in-memory transport to prove navigation,
message history, search, composition, member presence, and theme switching
without a browser runtime.

The application can also connect to Discord through the documented Bot REST
API v10 and Gateway. It does not accept or emulate personal account tokens.

## Run

```powershell
flutter pub get
flutter run -d windows
```

## Connect Discord

1. Create an application and bot in the Discord Developer Portal.
2. Enable the Message Content Intent for the bot.
3. Install the bot in a server with View Channels, Read Message History, and
   Send Messages permissions.
4. Open Connections from the link icon in the Flucord server rail.
5. Enter the bot token. When remembering it, Flucord stores it through Windows
   Credential Manager rather than SQLite or application logs.

Flucord uses documented bot authorization, an explicit user agent, Gateway
intents, heartbeat/resume, and REST rate-limit retries. It deliberately does
not send private Discord-client headers such as `X-Super-Properties` or use
user-account token flows.

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
