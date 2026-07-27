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
61. Completed: bind every authenticated Social SDK session to its crash-safe
    `GetCurrentUserV2()` snowflake and verify it against the linked OAuth
    identity before exposing friends, Direct Messages, or presence. Reject and
    clear only mismatched native grants so recovery reauthorizes the missing
    social step without discarding the verified OAuth profile.
62. Completed: carry the documented Social SDK-generated Discord avatar URL
    into relationship identities and open a responsive anchored friend profile
    with live presence, unique username, provisional-account context, copyable
    snowflake, Escape/outside dismissal, and direct navigation into the native
    DM surface. Reuse one identity-profile shell for friends and guild members.
63. Completed: retain the documented Social SDK `UserHandle::GameActivity()`
    snapshot with its application name, details, and party state; update it
    through the existing native user callback; and surface it in friend rows
    plus profiles. Keep the SDK's exact boundary visible: it exposes only Rich
    Presence associated with Flucord's Discord application, not every activity
    visible in the official client.
64. Completed: implement the documented Social SDK activity-invite lifecycle
    between Flucord sessions: create an ephemeral lobby, publish its join secret
    through Rich Presence, invite a friend, receive create/update callbacks,
    accept the exact invite object, and join the returned lobby secret. Surface
    incoming and joined state in Friends without presenting an activity lobby
    as an ordinary Discord DM call. Package-linked validation still needs the
    approved SDK.
65. Completed: attach documented Social SDK audio to the joined activity lobby
    with `StartCall(lobbyId)`, retain the native `Call`, synchronize connection
    status and participants, and expose self-mute, self-deafen, retry, and leave
    controls in the compact Friends strip. Keep call state memory-only and
    separate from normal DM state. The default unbundled Windows bridge remains
    release/smoke verified; package-linked compilation and live-account audio
    validation still require the separately approved SDK download.
66. Completed: synchronize documented per-user speaking changes from the
    retained Social SDK `Call`, clear speaking state when users stop or leave,
    and expose a responsive native participant panel with known friend avatars,
    identity fallbacks, speaking semantics, and live updates while open. Keep
    the default unbundled bridge verified. Audio-device selection remains after
    approved package headers expose exact enumeration and output signatures.
67. Completed: add documented per-participant local audio control through
    `Call::SetLocalMute`/`GetLocalMute`, carry the authenticated self identity
    through every call snapshot, reject self and stale participant targets, and
    expose independent mute/unmute progress, failure retry, and accessible
    state in the compact participant panel without suppressing speaking state.
    Keep local volume state memory-only and isolated from self mute/deafen.
68. Completed: statically inventory the installed Discord desktop 1.0.9249
    renderer protocol without reading account storage or message bodies. Add
    isolated, deterministic Dart builders for the observed REST headers and
    core chat operations plus Gateway v9 identify, resume, QoS heartbeat,
    READY/READY_SUPPLEMENTAL state, and byte-bounded opcode 37 guild
    subscriptions. ETF/zstd framing, a vault-owned account session, live
    socket integration, cache hydration, and interoperability validation remain.
69. Completed: establish an explicit native QR remote-auth session owned by
    Flucord, store the resulting desktop-user credential only in the operating
    system vault, and carry it through the versioned desktop REST and Gateway
    adapters. The vertical slice is complete only when the authenticated user,
    guild directory, guild channels, and channel history load through the
    existing native workspace without Electron, embedded Discord UI, copied
    Discord storage, or a Bot token. Windows WinHTTP upgrades, a live QR
    fingerprint, the main Gateway Hello, typed mandatory-hCaptcha handling, and
    an ephemeral system WebView2 challenge surface are implemented. Live phone
    approval, CAPTCHA completion, authenticated user/guild/channel/history
    hydration, Unicode-safe identity projection, and vault-backed restart
    restoration were verified on Windows against a test account.

70. Completed: replace JSON Gateway framing with the installed client's binary
    External Term Format encoding. A dependency-free Dart codec implements the
    erlpack subset the renderer's parser configuration describes, including the
    atom table, byte-array `STRING_EXT`, UTF-8 binaries, big integers, bit
    binaries, and explicit rejection of improper lists, payload compression,
    unsupported tags, truncation, trailing bytes, and unbounded nesting. The
    WinHTTP and `dart:io` sockets now carry binary frames in both directions,
    the encoding sits behind one framing contract that keeps JSON selectable,
    and opcode 37 batching counts encoded ETF bytes. The codec, decoder,
    encoder, and framing files hold 100% line coverage, and Discord's live
    Gateway acknowledged an ETF heartbeat Flucord encoded. `compress=zstd-stream`
    is deliberately omitted until a streaming Zstandard decoder exists.
71. Completed: add `tool/inventory_discord_bundles.ps1`, a reproducible static
    inventory of the installed desktop client, its 17 native modules, and the
    complete 4,614-chunk renderer corpus resolved through the webpack chunk map.
    It extracts endpoint constants, REST path segments, and Gateway dispatch
    events, classifies every one against `docs/DISCORD_BUNDLE_COVERAGE.md`, and
    fails when a Discord update introduces an unclassified capability.

72. In progress: lazy guild member lists. Static analysis of the installed
    renderer shows the current client never sends the legacy opcode 14; every
    member-list range travels in the bulk opcode 37 `channels` map. The
    transport and state layer is complete: `member_list_id` derivation through
    a server-supplied value, the `everyone` visibility class, or MurmurHash3
    x86-32 over the sorted `VIEW_CHANNEL` overwrite tokens; page-aligned range
    computation with the mandatory head page and half-viewport overscan; a
    five-channel per-guild subscription cache whose eviction is the
    unsubscribe; opcode 37 emission with unchanged-range suppression and
    reconnect replay; and the `SYNC`/`INVALIDATE`/`INSERT`/`UPDATE`/`DELETE`
    state machine over Discord's flat header-and-member row space. All seven
    new files hold 100% line coverage and the hash is pinned to twelve `mmh3`
    reference values. The controller and member-panel cut, plus live evidence
    for `GUILD_MEMBER_LIST_UPDATE`, remain.

73. Completed: negotiate `compress=zstd-stream` with a pure-Dart RFC 8878
    Zstandard decompressor, so the Gateway transport now matches the installed
    client exactly. Discord's `discord_zstd` native module cannot be
    redistributed, so the decoder is written from the format specification:
    frame and block framing, Huffman literals with FSE-coded weights, FSE
    sequences, repeat offsets, an amortized match window, and XXH64 content
    checksums. Transport compression and payload encoding sit behind one codec
    that resets both on reconnect, because a decompressor carried across
    sessions would resolve matches against stale history. Correctness is held by
    a committed libzstd 1.5.7 corpus, hand-built frames for the RLE block type
    libzstd never emits, a rejection corpus, 400 freshly generated random frames
    decoded one-shot and in random chunks, and fuzzing that requires every
    malformed input to surface as `ZstdException`. Validated live against the
    production Gateway end to end.

74. Completed: expand `READY.users` so Direct Messages have real people in
    them. Discord sends `private_channels[].recipient_ids` as bare ids to be
    resolved against a flat `READY.users` table; Flucord never built that table,
    so compressed DM channels arrived with no recipients and were dropped
    outright, leaving the sidebar empty. The table is now built per READY and
    cleared after `READY_SUPPLEMENTAL`, whose `lazy_private_channels` are
    ingested instead of discarded, and the DM list is ordered newest-first by
    the effective last-message snowflake. Hydration is fed independently of the
    bootstrap completer, because gating it there silently dropped every
    supplemental that arrived after the first snapshot. A replayed READY now
    also clears guild state, since the replay is authoritative.
75. Completed: open the text chat that lives inside a voice channel. A voice
    channel exposes both the voice room and its ordinary timeline through one
    keyboard-reachable switch, reusing the existing message list and composer,
    and the app-wide filters that treated voice channels as chat-less were
    revisited one by one. Threads and pins stay absent there, matching the
    permission set Discord grants a voice channel's chat, and the composer drops
    the hash because `#name` does not resolve to a voice channel.

76. Fixed: a compressed Gateway frame can expand to several payloads, and the
    reader accepted only one, rejecting the rest as trailing bytes and dropping
    the whole frame. When that frame carried `READY` the workspace never loaded
    and the client reported Discord as unreachable. The transport now decodes a
    batch per frame. `compress=zstd-stream` is disabled by default until it has
    been proven against a full authenticated session; the decoder, its corpus,
    and the live check all remain.

77. Completed: server voice channels work on the desktop-user session. Voice is
    now part of the `ChatRepository` contract instead of something callers
    discover by testing an implementation's class, and the desktop repository
    carries it on the socket that already delivers messages. Opcode 4 gained the
    two fields it was missing, opcode 5 `VOICE_SERVER_PING` answers a
    will-reconnect disconnect once per transition rather than on every repeat,
    and a voice-state roster seats the people already in a room when you walk
    into it. A `GUILD_CREATE` snapshot and a replayed `READY` now report who is
    no longer there, because a snapshot is the only notice of a departure that
    happened while the socket was down.
78. Completed: the member panel renders the server's real roster. Lazy
    subscriptions follow the panel's scroll position, `GUILD_MEMBER_LIST_UPDATE`
    feeds the row store, and group headers, counts and unloaded placeholders
    come from the server rather than from grouping a cached list locally. A
    server-supplied row index is now bounded before it is used to size the row
    space.
79. Completed: `lib/src/data/zstd` reaches full guard coverage through frames
    hand-built to trip each check, validated against the reference decoder.
    A decompression failure now reconnects instead of being logged and skipped:
    the stream is one continuous context, so once it desynchronises every later
    frame decodes against poisoned history while the socket still looks healthy.

80. Completed: calls in Direct Messages and group DMs. `VoiceSignalingService`
    was keyed by guild throughout, which a call has none of, so the key became a
    value that is either a guild or a private channel rather than a string a
    channel id could quietly impersonate. Opcode 13 `CALL_CONNECT`, the
    `CALL_CREATE`/`UPDATE`/`DELETE` dispatches and the three
    `/channels/{id}/call` routes drive an incoming-call surface, ringing, and a
    call that reuses the existing voice room. An outgoing ring now survives the
    `CALL_CREATE` that answers our own join: that frame reports nobody ringing
    because the server has not processed the ring yet, and treating it as
    "answered" meant the caller never saw Ringing and hanging up retracted
    nothing.
81. Completed: a user settings surface over `/users/@me/settings-proto`, with a
    hand-written reader and writer for the protobuf wire types those messages
    use — no dependency added, every length bounded before it is trusted. A
    partial `USER_SETTINGS_PROTO_UPDATE` arriving before the full blob is now
    ignored rather than installed as the root, which had made the repository
    look loaded while holding a fraction of the settings and skipped the fetch
    that would have filled in the rest.
82. Completed: permission computation. Flucord showed every channel and enabled
    every action because it never computed permissions; now channel visibility,
    composer enablement and the offered message actions all follow the
    `@everyone` role, the member's roles and the channel overwrites, with
    `ADMINISTRATOR` short-circuiting. A permission field is unsigned on the
    wire, so a negative value is refused: two's complement would have set every
    bit and failed open into full administrator rights.
83. Completed: server read state. Unread lived only on this machine, so it died
    with a reinstall and never agreed with the official client. `READY` now
    hydrates the read states and the per-guild notification settings, the five
    ack dispatches and `USER_GUILD_SETTINGS_UPDATE` keep them current, reading a
    channel acknowledges it to Discord on the same 3 s debounce the official
    client uses, and the rail pips, the NEW divider and the Inbox all read the
    server's answer. Notification settings — mute with its expiry, the
    per-channel and per-guild level, suppress `@everyone` and mobile push — are
    editable from the sidebar and gate the desktop notification path. Unread is
    a snowflake comparison against the channel's last message, never a numeric
    one: `int.parse` on a snowflake loses the low bits and would call a read
    channel unread forever.

83. Completed: server settings and moderation. Roles with the hierarchy rule,
    channels with position batching, bans, invites, the audit log, reporting and
    blocking, each section shown only when its own permission bit is held. A
    permission the account does not itself hold can no longer be granted through
    a role it controls, and an untouched Overview form no longer clears the
    guild's AFK and system channels: null is a real value for those, so it could
    not also mean "not edited".
84. Completed: server-side message search. The old search filtered only what was
    already loaded, which is an arbitrary slice of a channel. The typed query
    model carries the documented parameter set, hit groups render with their
    surrounding context, and a 202 is treated as "still indexing" rather than as
    an empty result.
85. Completed: presence and activities. Status, the client_status platform map,
    rich-presence activities with their timings and assets, custom status with
    an expiry, and the account's own status published on opcode 3. An expired
    custom status now stops being broadcast: composition honoured the deadline
    but nothing recomposed once it passed.
86. Completed: server read state. Unread state was local only, so it never
    survived a reinstall and never agreed with the official client. It now
    hydrates from READY, acknowledges to the server, and carries notification
    overrides. Sending a message reads its own channel, marking a guild read
    only acks what is actually unread, and the rolling ack token resets on
    reconnect rather than being replayed from a dead session.

87. Fixed: login reached the workspace again. 0.0.2 shipped ETF together with
    zstd; when zstd was withdrawn the release became ETF-without-compression, a
    combination no version had ever run against a real account. The live check
    only ever decoded a `HELLO`, which is a handful of terms, where a real
    `READY` is where the term vocabulary is first exercised at size. The shipped
    default is JSON again until a full authenticated session has proved ETF.
    The connection surface now reports the transport's own failure instead of
    one fixed sentence — showing only "Discord is unreachable" is what left two
    broken releases undiagnosable from the outside.

## Protocol boundaries

- Keep documented Bot, OAuth, and Social SDK transports independent from the
  experimental desktop-protocol adapter.
- Never extract account tokens, cookies, browser storage, or another running
  process's socket. A future credential source must be explicit and vault-owned.
- Treat installed-client headers and build numbers as a versioned runtime
  snapshot. Matching them does not establish account-ban immunity.
- Store supported session credentials with the operating system credential
  vault and keep transport secrets out of logs and SQLite.
- Restrict WebView2 to the mandatory hCaptcha surface: no Discord application
  UI, no credential storage, no permissions or popups, and immediate cleanup.
- Keep rate-limit handling and Gateway reconnect behavior covered by tests.
- Add OAuth2 only for scopes explicitly supported by Discord's public API.

## Non-goals for the tracer bullet

- Calling Discord's undocumented user endpoints.
- Voice, video, screen sharing, or overlay support.

These non-goals applied to the first local tracer bullet. Private desktop
protocol work now advances only through isolated, versioned adapters with
explicit credential ownership and regression coverage.

## Release 0.0.1

1. Audit the complete reachable Git history, commit metadata, tracked assets,
   and screenshot metadata for credentials and personal information.
2. Keep the audit reproducible as a local PowerShell command and a mandatory
   release-workflow gate.
3. Build and package the complete Windows release directory from an exact,
   checksum-verified Flutter toolchain.
4. Generate detailed release notes from GitHub pull requests, contributors,
   merge history, first-parent history, the complete commit range, and build
   provenance.
5. Publish the signed Git tag and checksum-addressed Windows archive through a
   tag-triggered GitHub Actions release.
