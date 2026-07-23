# Flucord

Flucord is a native Flutter desktop messaging client for Windows. It provides
server and channel navigation, searchable message history, replies,
attachments, reactions, message editing and deletion, active threads, member
roles and presence, typing indicators, local unread markers, paginated pinned
messages, Windows notifications, close-to-tray behavior, channel deep links,
signed updates, native voice-device diagnostics, desktop capture preview,
documented Discord CDN guild/member identity, and theme switching without a
browser runtime.

The application can also connect to Discord through the documented Bot REST
API v10 and Gateway. It does not accept or emulate personal account tokens.

## Run

```powershell
flutter pub get
flutter run -d windows
```

## Connect Discord

1. Create an application and bot in the Discord Developer Portal.
2. Enable the Message Content, Server Members, and Presence intents for the
   bot in the Developer Portal.
3. Install the bot with View Channels, Read Message History, Send Messages,
   Attach Files, Add Reactions, and Pin Messages permissions. Manage Messages
   is required only when deleting messages written by other members.
4. Open Connections from the link icon in the Flucord server rail.
5. Enter the bot token. When remembering it, Flucord stores it through Windows
   Credential Manager rather than SQLite or application logs.

Flucord uses documented bot authorization, an explicit user agent, Gateway
intents, heartbeat/resume, and REST rate-limit retries. It deliberately does
not send private Discord-client headers such as `X-Super-Properties` or use
user-account token flows.

Discord bots can edit only messages they authored. The UI exposes inline edit
for the connected bot's messages and lets Discord enforce channel-specific
permissions for deletes, uploads, and reactions.

Unread and mention markers are maintained locally for the running Flucord
session. Discord does not publish a bot API for a personal account's read
state, so these markers do not synchronize with the official Discord client.

Guild icons, global user avatars, guild-specific member avatars, and Discord's
default avatars use documented public CDN routes. Their URLs persist in the
SQLite v4 cache; unavailable images fall back to deterministic initials without
changing navigation, message, member-list, or voice-room geometry.

## Native Media

Opening a voice channel initializes the native Windows WebRTC media layer. The
voice surface supports microphone mute, input/output device selection,
screen/window source selection, live desktop-capture preview, and deterministic
track teardown. This path uses native WebRTC textures and devices, not a web
view.

For Discord repositories, Flucord also performs the documented main Gateway
voice-state exchange, Voice Gateway v8 heartbeat and resume flow, UDP address
discovery, AEAD mode negotiation, and DAVE MLS signaling through the bundled
official `libdave.dll`. The voice surface reports joining, connection,
discovery, DAVE negotiation, reconnect, failure, and encrypted transport-ready
states. Mute changes use a voice-state update without rebuilding the voice
session.

Encrypted transport readiness now activates a native audio uplink. Flucord
captures 48 kHz stereo PCM16 without a browser runtime, frames it into 20 ms
packets, encodes Opus with the bundled native libopus, applies DAVE and RTP,
then sends it through Discord's AES-256-GCM or XChaCha20-Poly1305 RTP-size UDP
transport. Mute and disconnect finish the speaking burst before the microphone
or voice session is torn down.

The receive boundary maps speaking SSRCs to users, reorders RTP across sequence
wrap, rejects duplicate/replayed packets, decrypts DAVE, and keeps independent
Opus decoder state per remote user. Bounded loss uses native Opus PLC/FEC;
long gaps reset only the affected user's decoder. Decoded PCM plays through
per-user native SoLoud streams with a 60 ms playout buffer and live Windows
output-device switching.

The media path is implemented end to end, but real Discord interoperability
still needs verification in an actual bot voice session before the project can
claim production-ready calls. Screen capture is currently a local preview and
is not sent to Discord.

## Verify

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter test integration_test/voice_playback_smoke_test.dart -d windows
flutter build windows --release
```

The release executable is written to
`build\windows\x64\runner\Release\flucord.exe`.

## Windows Integration

Flucord registers links in this form and forwards them to the existing app
instance:

```text
flucord://channels/{serverId}/{channelId}
```

Incoming messages raise native Windows notifications while Flucord is not
focused. Clicking a notification restores the window and opens its channel.
Closing the window hides it in the notification area; use `Quit Flucord` from
the tray menu to stop the process.

Automatic updates are disabled unless a release is built with an HTTPS
WinSparkle appcast:

```powershell
flutter build windows --release `
  --dart-define=FLUCORD_UPDATE_FEED_URL=https://updates.example.com/appcast.xml
```

The checked-in `dsa_pub.pem` verifies Windows update signatures. The matching
`dsa_priv.pem` is intentionally ignored by Git and must be backed up as a
release secret. Sign every installer before adding its signature to the
appcast:

```powershell
dart run auto_updater:sign_update .\dist\flucord-setup.exe
```

## Structure

- `lib/src/domain`: immutable entities and the transport contract.
- `lib/src/data`: transport implementations.
- `lib/src/application`: isolated remote and local state controllers.
- `lib/src/data/webrtc_voice_media_service.dart`: native device and capture
  implementation behind the voice media contract.
- `lib/src/presentation`: adaptive desktop workspace and focused widgets.
- `lib/src/theme`: shared surface, semantic color, and typography system.

See `roadmap.md` for the staged path from this local tracer bullet to a
production transport, platform integration, and voice.
