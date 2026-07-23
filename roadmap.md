# Flucord Roadmap

## Product intent

Flucord is a native Flutter desktop messaging client. The first tracer bullet
targets Windows and proves the core navigation and messaging loop without a
browser runtime or dependency on Discord's private user API.

## Architecture constraints

- Keep every source file below 500 lines.
- Keep remote/server state behind an asynchronous repository contract.
- Keep synchronous workspace state in a separate controller.
- Keep domain models independent from Flutter widgets.
- Keep the initial transport deterministic and local so the UI and tests do not
  depend on network access.
- Add real transports as repository implementations, not widget changes.

## Tracer bullet

- Native Windows Flutter runner.
- Server and channel navigation.
- Searchable message history.
- Message composition and local sending.
- Member presence panel.
- Light and dark themes.
- Loading, empty, and error states.
- Unit and widget coverage for the primary interaction loop.

## Later increments

1. Completed: persisted SQLite cache, secure bot credentials, REST API v10,
   Gateway heartbeat/resume, live message create/update, and offline fallback.
2. Completed: multipart attachments, replies, reaction add/remove, inline
   edits, confirmed deletes, active thread discovery, live Gateway updates,
   and SQLite v2 migration.
3. Completed: paginated pins with the 2026 `PIN_MESSAGES` permission, guild
   member and role loading, initial/live presence, typing expiry/throttling,
   and local unread/mention state.
4. Completed: native Windows notifications, close-to-tray behavior,
   single-instance `flucord://` channel deep links, and a configurable HTTPS
   WinSparkle feed with an embedded DSA verification key. Platform code stays
   behind application-owned service contracts so chat state and presentation
   remain independently testable.
5. In progress: native voice-room controls, device selection, local microphone
   capture, desktop preview, and deterministic teardown are complete. The app
   now sends documented main Gateway voice-state updates, assembles voice
   credentials, connects to Voice Gateway v8, performs UDP discovery, negotiates
   Discord's AEAD transport, and drives an official libdave MLS session. The UI
   exposes each signaling stage without presenting transport readiness as live
   audio. Native DAVE frame cryptors, epoch ratchet rotation, remote-user SSRC
   mapping, and an RTP v2 audio packetizer/parser are implemented behind typed
   boundaries. AES-256-GCM and mandatory XChaCha20-Poly1305 RTP-size transport
   encryption now protect the typed UDP send/receive boundary, including CSRC
   and RTP extension handling. Native 48 kHz stereo PCM16 capture, deterministic
   20 ms framing, bundled libopus encoding, readiness-gated DAVE/RTP uplink,
   speaking teardown, bounded per-SSRC RTP reordering, replay rejection,
   per-user remote Opus decoding, native PLC/FEC, a 60 ms playout buffer,
   per-user native PCM playback, and selected output-device routing are
   implemented. Documented main-Gateway voice-state updates now maintain an
   isolated participant roster with mute, deafen, stream, and video state;
   Voice-Gateway speaking flags drive the live participant border in a
   responsive Discord-like call grid. Discord interoperability testing in an
   actual bot voice session and transmitted screen sharing remain.
6. Completed: documented Discord CDN guild icons, global avatars, and
   guild-specific member avatars flow through immutable identity models,
   SQLite v4, messages, pins, member lists, the server rail, and voice rooms.
   Network failures retain deterministic initials without shifting layout.
7. Completed: documented Discord message embeds now survive REST history,
   partial Gateway updates, and SQLite v5. The message and pins surfaces render
   author/provider metadata, title, description, adaptive inline fields,
   source color, image/thumbnail error states, footer, and timestamp while
   preserving video metadata for a later native player.
8. Completed: channel history uses Discord's documented `before` cursor in
   bounded 100-message pages. Older pages merge without duplicate IDs, append
   to SQLite instead of replacing newer history, fall back to cached cursor
   slices offline, and preserve the visible timeline anchor when prepended.
9. macOS and Linux packaging after Windows behavior stabilizes.

## Protocol safety

- Use only documented Discord bot REST and Gateway contracts.
- Never accept personal account tokens or impersonate official client headers.
- Store bot credentials with the operating system credential vault.
- Keep rate-limit handling and Gateway reconnect behavior covered by tests.
- Add OAuth2 only for scopes explicitly supported by Discord's public API.

## Non-goals for the tracer bullet

- Calling Discord's undocumented user endpoints.
- Voice, video, screen sharing, or overlay support.

These non-goals applied to the first local tracer bullet. Private user
endpoints remain outside the product contract.
