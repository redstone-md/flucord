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
9. Completed: native rich message content renders Discord Markdown in the
   timeline, pins, and embed text, with resolved user/channel/role mentions,
   custom emoji, localized timestamps, application commands, spoilers, and
   external HTTPS links without a browser runtime. Role identity persists in
   SQLite v6, and channel mentions reuse the native workspace navigation path.
10. Completed: Windows-native inline video for Discord attachments and embed
    video metadata, with stable responsive geometry, explicit loading/error
    states, play/pause, mute, seek, duration, fullscreen, and deterministic
    teardown. A local MP4 integration smoke verifies the native texture and
    playback commands without network access or an embedded browser surface.
11. Completed: documented bot Direct Messages with the required Gateway
    intents, proactive REST channel creation by recipient ID, live DM channel
    discovery, recipient identity, unread state, and SQLite restoration. Bot
    READY payloads intentionally do not expose an open-DM list, so cached and
    live channels form the native inbox without private user endpoints.
12. In progress: macOS and Linux Flutter runners, platform assets, plugin
    registration, sandbox capabilities, and a cross-platform native video
    bundle are configured without changing the verified Windows path. Release
    builds still require verification on native macOS and Linux hosts.
13. Completed: documented Discord category channels and channel positions flow
    through Gateway updates, immutable workspace state, SQLite, and a
    collapsible Discord-like channel sidebar.
14. Completed: the desktop workspace uses Discord's neutral rail/sidebar/chat
    hierarchy, blurple interaction states, semantic presence and mention
    colors, and the familiar account panel placement without changing
    transport behavior.
15. Completed: local unread and mention state is aggregated per guild and DM
    space into Discord-like server rail pips, numeric badges, tooltips, and
    accessible navigation labels.
16. Completed: each local unread burst retains its first message ID through
    the domain model and SQLite v9. Opening a channel clears rail/sidebar
    counters without discarding the in-timeline marker; the message surface
    adds a Discord-like NEW divider and direct navigation to that boundary.
17. Completed: guild member rows open an anchored native profile popover
    with guild identity, presence, role, copyable user ID, keyboard dismissal,
    and a direct transition into the documented bot DM flow.
18. Completed: a native Discord-style Quick Switcher projects guilds,
    Direct Messages, text and voice channels, and active threads into one
    searchable destination catalog. The overlay preserves local unread and
    mention state, supports Ctrl+K, arrow-key, Enter, Escape, mouse, and screen
    reader navigation, and routes through the existing workspace/chat boundary.
19. Completed: a native Discord-style Inbox retains exact current-bot mention
    messages through Gateway, REST history, and SQLite v10, aggregates unread
    channels across every space, exposes a familiar header activity control,
    supports mark-all-read, and jumps from unread or mention entries into the
    native timeline.
20. Completed: documented guild emoji load through REST, update through
    Gateway, persist in SQLite v11, and feed a searchable native composer
    picker that inserts Unicode or Discord custom-emoji syntax at the caret.

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
