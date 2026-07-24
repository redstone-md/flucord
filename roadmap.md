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
- Keep deterministic demo data behind an explicit demo bootstrap so production
  never presents synthetic servers as real Discord state.
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
21. Completed: message hover actions reuse the searchable guild-aware picker
    for Unicode and documented `name:id` custom reactions. The anchored overlay
    survives pointer transfer from the message, and known custom reactions
    render as stable native glyphs instead of raw identifiers.
22. Completed: start a documented public thread from an existing message,
    persist the returned channel, project it into Active threads, and navigate
    directly into the new native conversation from a compact creation dialog.
    The dialog validates Discord's name limit, exposes all documented
    auto-archive durations, and retains loading and failure states in place.
23. Completed: retain Discord thread archive metadata in SQLite v12, page the
    documented public archived-thread route, and expose active plus archived
    branches in a native header Threads panel with direct timeline navigation,
    compact-window states, and locked archive handling.
24. Completed: retain documented Discord forum and media channel types,
    tags, defaults, and layouts in SQLite v13; render active and archived posts
    in a responsive native feed; filter by tags; create a text starter post
    through the documented forum-thread endpoint; and navigate directly into
    the existing native thread timeline.
25. Completed: create forum and media posts with up to ten native file-picker
    attachments, reuse one encapsulated pending-attachment selection surface
    across both composers, support attachment-only starter messages, and send
    the documented nested message metadata and files as multipart form data.
26. Completed: honor forum list and gallery metadata with stable responsive
    card geometry, render real starter-image previews plus video/file and error
    fallbacks, and lazily hydrate visible post previews through the existing
    history repository and SQLite cache without changing active navigation.
27. Completed: retain documented Discord message polls in SQLite v14, create
    polls through the Bot REST API, expire application-authored polls, apply
    Gateway vote add/remove events live, and render native responsive results
    in timelines, pinned messages, and poll-only Inbox previews. Voting remains
    absent because Discord exposes no documented bot mutation for casting one.
28. Completed: retain documented guild sticker catalogs and message sticker
    items, synchronize catalog replacements through `GUILD_STICKERS_UPDATE`,
    send up to three guild sticker IDs through Create Message, and expose a
    searchable native picker plus browser-free inline rendering.
29. Completed: load documented guild scheduled events with subscriber counts,
    persist them in SQLite v16, apply create/update/delete and subscriber
    Gateway events live, and expose a native server-level Events surface with
    direct navigation to associated voice and stage channels.
30. Completed: retain documented Discord message types and references in
    SQLite v17, preserve them across partial Gateway updates, and render native
    timeline rows for join, pin, boost, thread, stage, subscription, discovery,
    and incident system messages.
31. Completed: retain documented normal and burst reaction metadata, page
    reacting users through Get Reactions with type and snowflake cursors, and
    expose a compact native reaction ledger with retry-safe pagination.
32. Completed: retain documented forwarded-message references and immutable
    snapshots in SQLite v18, preserve them across partial Gateway updates,
    render their native content without inventing an absent author, and forward
    supported messages through the documented Create Message reference into a
    searchable text/DM/thread destination with loading, failure, and direct
    navigation states.
33. Completed: retain documented message flags in SQLite v19, enforce
    idempotent Create Message nonces, expose native silent sending through
    `SUPPRESS_NOTIFICATIONS`, and suppress or restore embeds through the
    documented Edit Message flags contract.
34. Completed: retain documented voice-message duration and waveform metadata
    through REST, partial Gateway updates, forward snapshots, and SQLite; render
    audio attachments through a compact native waveform player with seek,
    buffering, retry, responsive geometry, and deterministic teardown; and
    prevent edits forbidden by Discord. Record native 48 kHz stereo PCM, encode
    it through the bundled libopus boundary, mux deterministic Ogg/Opus, sample
    the documented base64 waveform, and upload the exact voice-message multipart
    contract. The composer owns record, cancel, stop-and-send, retained retry,
    channel-change cleanup, and compact-width states without browser surfaces.
35. Completed: project cached guild members, roles, channels, threads, and DM
    participants into a native caret-aware composer autocomplete. Rank matching
    names and metadata, insert documented mention syntax at the active range,
    and support mouse plus Up/Down, Enter, Tab, and Escape without stealing
    text-field focus or overflowing compact desktop layouts.
36. Completed: save remote file, image, video, and audio attachments through a
    native desktop destination dialog with streamed progress, cancellation,
    retry, server-filename sanitization, sibling partial-file cleanup, and
    replacement that preserves an existing destination until the response is
    complete and its byte count has been validated.
37. Completed: open image attachments in a native browser-free lightbox with
    shared download state, pan, bounded zoom, reset, desktop shortcuts,
    loading/error states, focus restoration, and compact-window geometry.
38. Completed: retain one encapsulated download-controller registry per
    message attachment set and navigate multi-image messages or forwarded
    snapshots inside the lightbox with bounded arrows, Left/Right shortcuts,
    a position counter, and zoom reset between images.
39. Completed: replace the generic raw bot-token connection path with typed
    Discord account sessions, explicit transport capabilities, a domain-owned
    repository factory, an explicit Bot adapter, and a versioned secure-vault
    codec that migrates the legacy bot-token key. Documented OAuth scopes remain
    capability-limited and cannot be mistaken for full chat/Gateway access.
40. Completed: separate Discord REST authorization into redacted Bot and OAuth2
    Bearer values behind one retry/rate-limit executor. Keep the full chat and
    `/gateway/bot` facade Bot-only, and add a scope- and expiry-gated OAuth
    identity tracer for documented `/users/@me` and `/users/@me/guilds` access.
41. Completed: add a native OAuth2 public-client lifecycle with PKCE S256,
    state-bound `flucord://` callbacks, client-secret-free code exchange,
    refresh-token rotation, a separate operating-system grant vault, restored
    profile/server metadata, and a native connection surface that cannot be
    mistaken for the Bot chat transport.
42. Completed: route channel links and OAuth callbacks through one typed desktop
    parser; add the declared macOS URL scheme; and implement Linux cold-start
    plus single-instance forwarded activation through a native GTK method
    channel and `x-scheme-handler/flucord` desktop entry. macOS/Linux release
    execution still requires verification on their native hosts.
43. Completed: move message preview construction, active-channel suppression,
    notification lifetime, and click routing into one native desktop controller;
    enable it on Windows, macOS, and Linux; and keep focus-driven unread state
    synchronized on every desktop host. Linux packaging requires `libnotify`.
44. Completed: replace the Windows-only tray path with one native desktop
    coordinator, materialize platform icon assets without bundle-path guesses,
    expose unread counts through the tooltip/menu, and provide Open/Quit on
    Windows, macOS, and Linux while preserving the Windows update action. Window
    close hides only after tray initialization succeeds; Linux packages require
    AppIndicator and GNOME needs its corresponding shell extension.
45. Completed: replace the production mock bootstrap and every connection
    failure fallback with an explicit disconnected repository, automatically
    restore a supported saved session, and isolate deterministic workspace data
    behind `FlucordApp.demo()`. The shell, account panel, and connection dialog
    now distinguish disconnected, demo, and Discord transport state without
    implying that linked OAuth identity grants message access.
46. Completed: preserve the documented normal-user OAuth guild directory as
    immutable domain data, request approximate counts through the paginated
    public endpoint, map server icons/banners and owner/admin context, and
    render the result as a bounded native list in Connections. Every row keeps
    the no-message-access boundary visible instead of conflating OAuth identity
    with the Bot chat transport.
47. Completed: promote a restored linked identity into a responsive native
    guild-directory workspace when no chat transport is connected. A dedicated
    client-state controller owns server selection; the Discord-like rail,
    sidebar, identity footer, and content header use real OAuth guild metadata,
    while locked channel/message surfaces keep unsupported data visibly absent.
48. Completed: request the documented `guilds.members.read` OAuth scope, load the
    current user's membership for the selected authorized server through the
    public Bearer endpoint, and project nickname, guild avatar, roles, join and
    boost metadata into the native workspace. Keep this asynchronous server
    state isolated from the guild-selection controller and cache it per guild.
49. Completed: request the documented `connections` OAuth scope, retain the
    current user's verified and visible third-party account directory as
    immutable server state, and expose it through a Discord-like account-home
    destination plus Connections settings without implying DM or friend access.
50. Completed: retain the documented current-user `identify` profile metadata,
    including legacy username context, banner, accent color, locale,
    verification, MFA, and public flags, then render a responsive native
    Discord-like profile header without requesting the optional email scope.
51. Completed: introduce a native Discord Social SDK capability boundary for
    relationship access without routing user features through Bot REST. The
    first Windows tracer bullet reports whether the separately distributed SDK
    is linked, keeps the default build functional when it is absent, and
    surfaces that exact state in Friends. Native SDK authentication and the
    live `GetRelationships()` call remain after an approved Developer Portal
    SDK package is available.
52. Completed: carry Social SDK relationships through immutable friend,
    request, presence, and provisional-user models; expose a typed native
    `getRelationships` channel contract; and replace the Friends placeholder
    with loading, empty, failure, request, online, and offline native states.
    The default runner returns an explicit unbundled error, while a linked
    runner returns authorization-required rather than fabricating relationships
    before SDK authentication is verified against the approved package.
53. Completed: add typed Social SDK relationship mutations for accepting and
    rejecting incoming requests, cancelling outgoing requests, removing
    friends, and blocking users. Keep per-user pending and failure state in the
    Friends controller, require confirmation for destructive actions, and keep
    unsupported native builds explicit instead of applying local-only changes.
54. Completed: authenticate the Windows Social SDK client through its native
    public-client PKCE flow, rotate refresh grants in a dedicated operating-
    system credential vault, pump SDK callbacks on the runner UI thread, and
    connect Friends only after the SDK reaches `Ready`. The authenticated
    bridge exposes live relationships and mutations without sharing OAuth or
    Bot credentials. Package-linked compilation and live-account validation
    still require the separately approved SDK download.
55. Completed: add an authenticated Social SDK Direct Message tracer bullet
    with conversation summaries, bounded message history, exact-content
    sending, and live create/update/delete synchronization. The native account
    workspace now exposes a Discord-like DM sidebar, friend-to-chat navigation,
    chronological timeline, and 2,000-character composer while keeping this
    user-account transport independent from the Bot repository. The default
    Windows runner and its unbundled-SDK contract are release/smoke verified;
    package-linked compilation and live-account validation still require the
    separately approved SDK download.
56. Completed: add official Social SDK editing and deletion for messages
    authored by the current user, including per-message pending/failure state,
    confirmed local projection across refresh failures, and Discord-like hover
    plus inline-edit controls. `SetShowingChat` now follows native DM visibility
    and Flutter desktop lifecycle, so the Discord desktop app suppresses
    duplicate notifications only while Flucord actively presents chat.
57. Completed: synchronize friend identity and presence changes through the
    documented Social SDK user-update callback, and expose the official online,
    idle, do-not-disturb, and invisible status mutation from the native account
    footer. Keep this live user path independent from Bot Gateway presence and
    preserve the unbundled Windows runner contract.
58. Completed: send standard Discord friend requests by documented user ID,
    synchronize created and relationship-group changes live, and expose a
    Discord-like Add Friend action with pending, validation, and failure states.
    Direct user voice calling remains outside the public contract because the
    documented call API requires a lobby/channel ID that user-DM summaries do
    not expose.
59. Completed: make the normal desktop build a user-account-only surface by
    disabling Bot session restoration and connection at the application
    boundary. Retain the documented Bot adapter only behind the explicit
    `FLUCORD_ENABLE_BOT_TRANSPORT=true` developer flag and a collapsed,
    separately labelled settings section.
60. Completed: coordinate ordinary OAuth and native Social SDK authorization
    through one normal-account connect, completion, and disconnect surface.
    Keep both grants, refresh lifecycles, vaults, and failure states independent
    while routing Friends recovery through the same account coordinator.

## Protocol safety

- Use only documented Discord bot REST and Gateway contracts.
- Never accept personal account tokens or impersonate official client headers.
- Store supported session credentials with the operating system credential
  vault and keep transport secrets out of logs and SQLite.
- Keep rate-limit handling and Gateway reconnect behavior covered by tests.
- Add OAuth2 only for scopes explicitly supported by Discord's public API.

## Non-goals for the tracer bullet

- Calling Discord's undocumented user endpoints.
- Voice, video, screen sharing, or overlay support.

These non-goals applied to the first local tracer bullet. Private user
endpoints remain outside the product contract.
