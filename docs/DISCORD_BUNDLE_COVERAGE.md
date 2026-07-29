# Discord bundle capability coverage

This ledger tracks Flucord's coverage of the capabilities that are statically
discoverable in the installed Discord desktop client and its renderer bundles.
It is regenerated and gated by `tool/inventory_discord_bundles.ps1`.

```powershell
.\tool\inventory_discord_bundles.ps1
```

The tool writes [`discord_bundle_inventory.json`](discord_bundle_inventory.json)
and exits non-zero when the bundle exposes a REST path segment or Gateway
dispatch event that no ledger row below claims. Updating Discord therefore
forces this document to be updated too.

## Method and boundaries

Static analysis only:

- The installed program directory `app-<version>` is hashed. `Discord.exe`,
  every `modules/*` package, and each `.asar`/`.node`/`.dll` inside it are
  recorded by name, size, and SHA-256.
- The renderer corpus is fetched from Discord's public asset host. The entry
  chunk's webpack chunk map is parsed to enumerate every lazily loaded chunk, so
  the corpus is the complete shipped renderer, not just the preloaded subset.
- Discord's Local Storage, Session Storage, Cookies, `Network` cache,
  credential records, message content, and running processes are never read.
  No Discord JavaScript, asset, or string table is copied into Flucord.

Extraction rules, in the exact form the tool applies them:

| Symbol set | Rule |
| --- | --- |
| Endpoint constants | `NAME: <template or literal starting with />` across every chunk |
| Path segments | first path segment of each endpoint constant |
| Gateway dispatch events | arrays of `SCREAMING_SNAKE` literals passed to the entry chunk's dispatch registrar, anchored on `READY_SUPPLEMENTAL` |
| Native modules | directory names under `app-<version>/modules` |

Known bound: Flux stores inside lazily loaded chunks register additional
dispatch handlers whose registrar identity is not recoverable from minified
code without symbol reconstruction. Those events are **not** counted as
discovered, and no ledger row may claim them. This is a limit of static
extraction, stated rather than papered over.

## Snapshot

| Measure | Value |
| --- | --- |
| Installed client | `1.0.9249` |
| Client build number | `582977` |
| Renderer entry chunk | `web.3c742507ecdea9fa.js` |
| Renderer chunks analyzed | 4,622 |
| Renderer corpus bytes | 157,511,089 |
| Endpoint constants | 957 |
| Endpoint path segments | 165 |
| Gateway dispatch events | 175 |
| Native desktop modules | 17 |

## Coverage

| Metric | Value | Definition |
| --- | --- | --- |
| Discovery coverage | **100.00%** | classified segments and events / discovered segments and events (340/340) |
| Implementation coverage | **10.53%** | applicable domains verified complete / applicable domains (2/19) |
| Partial domains | 15 of 19 applicable | at least one vertical slice shipped, remainder open |
| Automated test coverage | 89.27% lines | `flutter test --coverage`, 2,168 passing, 6 skipped |

Implementation coverage counts only domains with a verified end-to-end vertical
slice for **every** capability in the domain. A domain with shipped slices but
open capabilities counts as partial, not implemented.

Two domains are marked not applicable, with reasons stated in their rows. They
are excluded from the denominator and are never reported as implemented.

## Status values

- **Implemented** — domain complete: domain model, repository/data boundary,
  controller, UI, automated tests, and live evidence for every capability.
- **Partial** — at least one complete vertical slice; named gaps remain.
- **Absent** — no vertical slice.
- **Not applicable** — cannot be exercised by an independent native client; the
  row states the exact reason.

---

## FBC-GATEWAY — Gateway transport and session lifecycle

- **Bundle evidence**: `web.3c742507ecdea9fa.js` socket module; native
  `discord_erlpack`, `discord_zstd` modules.
- **Symbols**: `READY`, `READY_SUPPLEMENTAL`, `RESUMED`, `SESSIONS_REPLACE`,
  `STATE_UPDATE`, `DELETED_ENTITY_IDS`.
- **Purpose**: authenticated real-time session, hydration, resume.
- **UI surface**: connection state in the shell and account panel.
- **Contract**: `wss://gateway.discord.gg?encoding=etf&v=9&compress=zstd-stream`;
  opcodes 0/1/2/6/7/9/10/11, bulk subscriptions 37, QoS heartbeat 40.
- **Dependencies**: none.
- **Status**: **Partial**.
- **Implemented**: the transport now matches the installed client exactly.
  External Term Format encode/decode; a pure-Dart RFC 8878 Zstandard
  decompressor for `compress=zstd-stream`; both behind one transport codec that
  resets them together on reconnect; binary WebSocket frames through the WinHTTP
  and `dart:io` connectors; identify/resume/QoS heartbeat;
  `READY`/`READY_SUPPLEMENTAL`/`GUILD_CREATE` hydration; opcode 37 batching
  measured in encoded ETF bytes.
- **Tests**: `discord_etf_codec_test.dart`, `discord_gateway_framing_test.dart`,
  `discord_gateway_transport_codec_test.dart`, `zstd_reference_test.dart`,
  `zstd_stream_reference_test.dart`,
  `discord_desktop_gateway_client_test.dart`,
  `discord_desktop_gateway_protocol_test.dart`. The ETF codec, decoder,
  encoder, and framing files are at 100% line coverage. The Zstandard decoder is
  checked against libzstd 1.5.7 through a committed corpus of 28 reference
  frames plus 7 frames that must be rejected, and was additionally validated
  against 400 freshly generated random frames decoded both one-shot and in
  random chunks, and against ~10,000 fuzzed mutations that must all surface as
  `ZstdException`.
  Line coverage of `lib/src/data/zstd` stands at **85%**, below the 100%
  this project requires of a new parser. The gap is guard clauses for
  malformed input that neither the conformance corpus nor random fuzzing
  reaches; closing it needs a frame hand-built per guard and is tracked as
  the next task on this domain rather than reported as done.
- **Live evidence**: `discord_desktop_gateway_live_test.dart` opens the real
  Gateway with `encoding=etf&v=9&compress=zstd-stream`, decompresses the live
  stream, decodes the `HELLO`, encodes an ETF heartbeat, and receives a real
  opcode 11 acknowledgement, on `2026-07-26`.
- **Blocked by**: dispatch coverage, not transport. `SESSIONS_REPLACE`,
  `STATE_UPDATE`, and `DELETED_ENTITY_IDS` are unhandled, and identify still
  sends an empty `client_state`, so Discord always answers with full-mode
  guilds instead of the versioned partial updates the renderer negotiates.

## FBC-ACCOUNT — Authentication, sessions, verification

- **Bundle evidence**: 53 endpoint constants across 21 segments including
  `auth`, `login`, `mfa`, `captcha`, `age-verification`, `wasntme`.
- **Symbols**: `AUTH_SESSION_CHANGE`, `AUTHENTICATOR_CREATE`,
  `AUTHENTICATOR_DELETE`, `AUTHENTICATOR_UPDATE`.
- **Purpose**: obtain and retain a desktop account session.
- **UI surface**: Connections, QR login dialog, hCaptcha challenge window, the
  Devices page in user settings.
- **Contract**: remote-auth Gateway v2, `POST /users/@me/remote-auth/login`,
  `X-Captcha-Key`/`X-Captcha-Rqtoken`/`X-Captcha-Session-Id`,
  `GET /auth/sessions`, `POST /auth/sessions/logout`,
  `POST /users/@me/mfa/totp/enable`, `POST /users/@me/mfa/totp/disable`,
  `POST /users/@me/mfa/sms/enable`, `POST /users/@me/mfa/sms/disable`,
  `POST /auth/verify/view-backup-codes-challenge`,
  `POST /users/@me/mfa/codes-verification`,
  `GET /age-verification/methods`, `POST /age-verification/verify`.
- **Dependencies**: FBC-GATEWAY.
- **Status**: **Partial**.
- **Implemented**: RSA-2048 QR remote auth, mandatory hCaptcha through an
  ephemeral system WebView2, versioned operating-system session vault. Also
  the Devices page — every session signed in to the account, and ending one or
  all of the others. Sessions are named by the hash Discord identifies them
  with, never by anything that could be turned back into a token. The current
  session is offered no end control, because ending it is signing out. Discord
  asking for the account password before it will end a session is reported as
  the refusal it is rather than as a fault: Flucord holds no password to offer
  it. Two-factor authentication is switched on and off from the Two-Factor
  page. The secret is minted locally from `Random.secure()` — twenty bytes,
  base32, the length Discord's own client uses — and reaches the server only
  alongside the first code that works, so Discord is never told about a secret
  the account has not proved it can use. It is shown once, held in memory
  only, dropped the moment the code is accepted or the page closes, and a
  second tap on "add" cannot swap it out from under the app it was just added
  to. A code Discord refuses is reported as the mistyped or expired code it
  usually is, not as a failure. Text messages are switched on and off as a
  second factor — Discord uses the number already on the account, so the page
  says so rather than offering a field nobody can fill. Backup codes can be
  read again or minted afresh: the password buys a pair of one-shot nonces and
  a current authenticator code spends one. The account password is typed for
  the single request that needs it, cleared from the field before that request
  is even sent, and held nowhere.
  Age verification lists the methods Discord offers the account and starts the
  one chosen, opening where Discord says it continues in the system browser.
  Each check is run by the third party Discord names, and the page says so
  before anything else on it: no document, photograph or wallet credential
  passes through Flucord, because none of it passes through the client at all.
  A method the account may not use is named as refused; one that finishes
  inside a vendor's own app says which vendor rather than leaving a button
  that appears to do nothing.
- **Tests**: `discord_remote_auth_gateway_test.dart`,
  `discord_desktop_login_controller_test.dart`, `auth_session_test.dart`,
  `auth_session_widget_test.dart`, `multi_factor_auth_test.dart`,
  `multi_factor_auth_widget_test.dart`, `age_verification_test.dart`,
  `age_verification_widget_test.dart`.
- **Live evidence**: phone approval, hCaptcha completion, encrypted session
  exchange, and restart restoration validated on Windows `2026-07-25`. The
  Devices page has none: listing another session needs a second one to exist.
- **Blocked by**: WebAuthn as a second factor, and the vendor-side half of
  age verification. Both need a native surface this build does not carry — the
  platform authenticator API for one, the identity vendors' own SDKs for the
  other. Account standing shipped under FBC-MODERATION.

## FBC-PROFILE — Current user, other users, user settings

- **Bundle evidence**: 213 endpoint constants across `users`, `settings`,
  `unique-username`, `badge-icons`.
- **Symbols**: `USER_UPDATE`, `USER_NOTE_UPDATE`, `USER_BADGE_STATE_UPDATE`,
  `USER_SETTINGS_PROTO_UPDATE`.
- **Purpose**: identity, profile cards, client settings synchronization.
- **UI surface**: account panel, member and friend profile popovers, user
  settings dialog.
- **Contract**: `GET /users/@me`, `PATCH /users/@me`,
  `GET /users/{id}/profile`, `GET`/`PATCH /users/@me/settings-proto/{n}`.
- **Dependencies**: FBC-GATEWAY.
- **Status**: **Partial**.
- **Implemented**: `READY` identity projection, guild member profile popover,
  OAuth `identify` profile header, `PreloadedUserSettings` read/write over a
  hand-written protobuf codec with `READY.user_settings_proto` and
  `USER_SETTINGS_PROTO_UPDATE` applied as whole-group replacements. Appearance,
  chat, notification, privacy, language and status groups are surfaced; each
  row states whether Flucord applies it, only stores it, or cannot honour it.
  The account's own profile is editable: display name, pronouns, about me,
  accent colour, avatar and banner over `PATCH /users/@me`, each image and the
  accent carried as untouched/set/cleared so an unrelated save cannot strip
  what nobody edited, every write adopting the server's echo, and `USER_UPDATE`
  from another device applied to the same store.
- **Tests**: `discord_oauth_account_mapper_test.dart`, `proto_wire_test.dart`,
  `discord_user_settings_codec_test.dart`,
  `discord_user_settings_repository_test.dart`,
  `user_settings_controller_test.dart`, `user_settings_widget_test.dart`,
  `user_settings_display_test.dart`, `user_profile_test.dart`,
  `user_profile_section_widget_test.dart`, `profile_image_picker_test.dart`,
  `widget_test.dart`.
- **Live evidence**: authenticated identity hydrated on Windows `2026-07-25`.
- **Blocked by**: `FrecencyUserSettings` (type 2) has no codec; offline-edit
  replay with `required_data_version` is not implemented; keybinds are not in
  `PreloadedUserSettings` at all and need a different capability; changing a
  username or password needs a password confirmation this client does not
  collect, so both are stated read-only rather than offered.

## FBC-PRESENCE — Presence and typing

- **Symbols**: `PRESENCE_UPDATE`, `PRESENCES_REPLACE`, `SESSIONS_REPLACE`,
  `READY.sessions`, `READY_SUPPLEMENTAL.merged_presences`, `TYPING_START`,
  opcode 3.
- **Purpose**: online state, activities, typing indicators.
- **UI surface**: member list, profile popovers, account panel, typing row.
- **Contract**: Gateway dispatches; opcode 3 `{status, since, activities, afk}`;
  opcode 37 `activities` subscription; `status` group of the settings proto.
- **Dependencies**: FBC-GATEWAY, FBC-GUILD, FBC-SETTINGS.
- **Status**: **Implemented**.
- **Implemented**: the per-user × per-guild presence map with R07's cross-guild
  collapse, offline pruning, activity comparator, duplicate-`PLAYING` filter and
  hidden-activity dedupe; the full activity model with assets, party,
  timestamps, emoji and buttons; `client_status` with the mobile indicator and
  the synthesised streaming status; `SESSIONS_REPLACE` and `READY.sessions`;
  `merged_presences` attributed per R03; outbound opcode 3 with the idle/AFK
  machine, the dirty check and the five-per-twenty-second window; status and
  custom-status writes through the settings proto.
- **Tests**: `discord_presence_mapper_test.dart`,
  `discord_presence_store_test.dart`, `discord_idle_tracker_test.dart`,
  `discord_self_presence_test.dart`, `discord_presence_updater_test.dart`,
  `discord_presence_service_test.dart`, `discord_presence_wire_test.dart`,
  `discord_desktop_presence_test.dart`, `user_presence_model_test.dart`,
  `presence_widget_test.dart`, `self_presence_controller_test.dart`.
- **Live evidence**: none for the desktop-user transport.
- **Not implemented**: the local activity producers R07 lists as separate
  concerns — game detection, Spotify sync, Go-Live and the RPC `SET_ACTIVITY`
  server — and the `BOT_HTTP_INTERACTIONS` status default, which needs user
  flags the presence payload does not carry.

## FBC-RELATIONSHIPS — Friends, blocks, direct-message directory

- **Symbols**: `RELATIONSHIP_ADD`/`REMOVE`/`UPDATE`, `FRIEND_SUGGESTION_*`,
  `GAME_RELATIONSHIP_*`, `CHANNEL_RECIPIENT_ADD`/`REMOVE`,
  `MESSAGE_REQUEST_NOTIFICATION_SENT`.
- **Purpose**: friend graph, blocked users, group DM membership.
- **UI surface**: Friends, DM sidebar.
- **Contract**: `READY.relationships`, `PUT/DELETE /users/@me/relationships`.
- **Dependencies**: FBC-GATEWAY.
- **Status**: **Partial**.
- **Implemented**: the full Discord Social SDK relationship path — list,
  add, accept, reject, cancel, remove, block, presence, and DMs.
- **Tests**: `social_sdk_*_test.dart` suite.
- **Live evidence**: unbundled-SDK contract release-verified; package-linked
  validation still requires the approved SDK download.
- **Blocked by**: the desktop-user transport does not yet project
  `READY.relationships`; Friends is served by the separate Social SDK session.

## FBC-GUILD — Servers, members, roles, discovery

- **Bundle evidence**: 194 endpoint constants across 18 segments.
- **Symbols**: `GUILD_UPDATE`, `GUILD_DELETE`, `GUILD_MEMBER_*`,
  `GUILD_MEMBERS_CHUNK`, `GUILD_MEMBER_LIST_UPDATE`, `GUILD_JOIN_REQUEST_*`,
  `GUILD_DIRECTORY_ENTRY_*`, and 6 more.
- **Purpose**: server list, member list, roles, onboarding, discovery.
- **UI surface**: server rail, member panel, server settings.
- **Contract**: `READY`/`GUILD_CREATE`; member-list ranges through the bulk
  opcode 37 `channels` map; `GET /guilds/{id}/members`.
- **Dependencies**: FBC-GATEWAY.
- **Status**: **Partial**.
- **Implemented**: guild directory, channel projection, role identity, guild
  icons, per-guild unread aggregation. Lazy member lists now have their full
  transport and state layer: `member_list_id` derivation (server-supplied
  value, the `everyone` visibility class, or MurmurHash3 x86-32 over the sorted
  `VIEW_CHANNEL` overwrite tokens), page-aligned range computation with the
  head page and half-viewport overscan, a five-channel per-guild subscription
  cache whose eviction is the unsubscribe, opcode 37 emission with
  reconnect replay, and the `SYNC`/`INVALIDATE`/`INSERT`/`UPDATE`/`DELETE`
  state machine over Discord's flat header-and-member row space.
- **Tests**: `discord_mapper_test.dart`, `discord_guild_member_loader_test.dart`,
  `discord_member_list_test.dart`, `discord_desktop_gateway_client_test.dart`.
  The seven new member-list files are at 100% line coverage, and the hash is
  checked against twelve `mmh3` reference values.
- **Live evidence**: guild and channel hydration on Windows `2026-07-25`. None
  yet for `GUILD_MEMBER_LIST_UPDATE` itself.
- **Blocked by**: `GET /guilds/{id}/members` enumeration, which is the bot
  route for walking a whole guild and is deliberately not used by a user
  session. Nothing else here is outstanding: the roster reaches the member
  panel, and opcode 8 with `GUILD_MEMBERS_CHUNK` now answers a mention being
  typed — a large guild sends a fraction of its members at login, so the names
  already loaded are not the names that can be mentioned, and typing an
  at-sign asks the guild about the rest. A guild nickname wins over a global
  name in what comes back, since that is the name everybody there sees.

> Correction, `2026-07-26`: an earlier revision of this row named opcode 14 as
> the member-list contract. Static analysis of `web.3c742507ecdea9fa.js` finds
> `GUILD_SUBSCRIPTIONS=14` in the opcode enum with **no call site** in any of
> the 4,614 chunks; every range subscription travels in opcode 37. Opcode 14 is
> a legacy enum entry in this build and its payload shape is not recoverable.

## FBC-CHANNEL — Channels, threads, forums

- **Bundle evidence**: 86 endpoint constants; `channels`, `threads`.
- **Symbols**: `CHANNEL_INFO`, `CHANNEL_MEMBER_COUNT_UPDATE`,
  `THREAD_MEMBER_UPDATE`, `THREAD_MEMBERS_UPDATE`, `THREAD_MEMBER_LIST_UPDATE`.
- **Purpose**: channel tree, categories, threads, forum and media posts.
- **UI surface**: channel sidebar, Threads panel, forum feed.
- **Contract**: `GUILD_CREATE.channels/threads`,
  `GET /channels/{id}/threads/archived/public`, forum thread creation,
  `GET /channels/{id}/thread-members`,
  `POST`/`DELETE /channels/{id}/thread-members/@me`.
- **Dependencies**: FBC-GATEWAY, FBC-GUILD.
- **Status**: **Partial**.
- **Implemented**: categories, positions, collapsible sidebar, active and
  archived threads, forum/media posts with tags, layouts, and attachments.
  Thread membership is joinable: the store is fed from the list route,
  `THREAD_MEMBER_UPDATE` — only ever about this account — `THREAD_MEMBERS_UPDATE`
  with its authoritative count, and the member object nested in a
  `THREAD_CREATE` for a thread made here. The desktop client posts rather than
  puts to join, and so does this.
- **Tests**: `discord_chat_repository_threads_test.dart`,
  `discord_chat_repository_forums_test.dart`, `thread_membership_test.dart`,
  `thread_membership_widget_test.dart`, `widget_test.dart`.
- **Live evidence**: channel history on Windows `2026-07-25`.
  The lazy roster arrives as `THREAD_MEMBER_LIST_UPDATE`, which names its
  thread on `thread_id` rather than `id` and replaces the held set because it
  is a whole snapshot.
- **Blocked by**: per-thread notification settings under
  `thread-members/@me/settings`.

## FBC-MESSAGE — Messages and message content

- **Bundle evidence**: `messages`, `attachments`, `unfurler`, `messages-log`.
- **Symbols**: `MESSAGE_REACTION_*`, `MESSAGE_POLL_VOTE_*`, `LAST_MESSAGES`,
  `SAVED_MESSAGE_CREATE`/`DELETE`, and 3 more.
- **Purpose**: the messaging loop itself.
- **UI surface**: timeline, composer, pins, lightbox, media players.
- **Contract**: `GET/POST/PATCH/DELETE /channels/{id}/messages[...]`.
- **Dependencies**: FBC-GATEWAY, FBC-CHANNEL.
- **Status**: **Implemented**.
- **Implemented**: history paging, send, edit, delete, attachments, replies,
  reactions with burst metadata, pins, embeds, polls, stickers, forwarding,
  message flags and nonces, voice messages, Markdown, mentions, downloads,
  native image/video/audio playback.
- **Tests**: 40+ files under `test/`, including
  `discord_chat_repository_messages_test.dart` and `discord_message_mapper_test.dart`.
- **Live evidence**: live channel history and message dispatches on Windows
  `2026-07-25`.
- **Blocked by**: nothing for this domain. Saved messages ride on
  FBC-READSTATE, which is tracked separately.

## FBC-READSTATE — Read state, mentions, notifications

- **Symbols**: `USER_GUILD_SETTINGS_UPDATE`, `USER_NON_CHANNEL_ACK`,
  `NOTIFICATION_CENTER_ITEM_*`, `FORUM_UNREADS`, `RECENT_MENTION_DELETE`,
  and 8 more.
- **Purpose**: unread boundaries, mention badges, notification centre.
- **UI surface**: rail pips, NEW divider, Inbox.
- **Contract**: `POST /channels/{id}/messages/{id}/ack`,
  `POST /read-states/ack-bulk`.
- **Dependencies**: FBC-GATEWAY, FBC-MESSAGE.
- **Status**: **Partial**.
- **Implemented**: server read state hydrated from `READY.read_state` (both
  entry dialects) and kept in step with `MESSAGE_ACK`, `CHANNEL_PINS_ACK`,
  `CHANNEL_PINS_UPDATE`, `GUILD_FEATURE_ACK`, `USER_NON_CHANNEL_ACK`,
  `USER_GUILD_SETTINGS_UPDATE` and `PASSIVE_UPDATE_V2`; channel ACK with the
  rolling token, day counter and flags on a 3 s debounce; mark-unread; the
  100-entry bulk pump; the guild- and user-scoped non-channel ACK routes;
  notification settings (guild and channel level, mute with its expiry,
  suppress `@everyone`, mobile push) reflected in the sidebar and rail and
  honoured by the desktop notification path; local unread and mention state,
  first-unread anchors, Inbox, mark-all-read.
- **Tests**: `read_state_model_test.dart`, `discord_read_state_codec_test.dart`,
  `discord_read_state_store_test.dart`,
  `discord_read_state_ack_queue_test.dart`,
  `discord_read_state_repository_test.dart`,
  `discord_desktop_rest_read_state_test.dart`,
  `discord_desktop_read_state_test.dart`,
  `chat_controller_read_state_test.dart`,
  `channel_sidebar_notifications_test.dart`.
- **Live evidence**: none for server-side acknowledgement.
- **Blocked by**: the notification centre (`NOTIFICATION_CENTER_*`) and message
  requests are still unmodelled, and the 30-day read-state garbage collector is
  not run — `DELETE /channels/{id}/messages/ack` exists as a route builder with
  no caller.

## FBC-EXPRESSION — Emoji, stickers, soundboard, GIF providers

- **Bundle evidence**: 21 endpoint constants across 9 segments.
- **Symbols**: `GUILD_EMOJIS_UPDATE`, `GUILD_STICKERS_UPDATE`,
  `GUILD_SOUNDBOARD_SOUND_*`, `SOUNDBOARD_SOUNDS`, and 3 more.
- **Purpose**: expression pickers and inline rendering.
- **UI surface**: composer picker, reaction picker, message rendering.
- **Contract**: `GET /guilds/{id}/emojis`, `GET /sticker-packs`,
  `GET /guilds/{id}/soundboard-sounds`, Tenor/Giphy/Klipy proxies.
- **Dependencies**: FBC-GUILD, FBC-MESSAGE.
- **Status**: **Partial**.
- **Implemented**: guild emoji catalogue with live updates, guild stickers,
  searchable pickers, inline custom-emoji rendering. The soundboard sends:
  a server's own sounds and the shared defaults are listed together and played
  into a voice channel over `POST /channels/{id}/send-soundboard-sound`, with
  `source_guild_id` carried only for a server sound because Discord refuses it
  on a default one. Sounds a server lost its boost level for stay listed and
  are refused locally rather than sent for a 403. Ids arrive as numbers for
  defaults and strings for guild sounds; both are read.
- **Tests**: `discord_chat_repository_emojis_test.dart`,
  `discord_chat_repository_stickers_test.dart`, `soundboard_test.dart`,
  `soundboard_widget_test.dart`.
- **Live evidence**: none for the desktop-user transport.
  An incoming effect is played: Discord never mixes a soundboard sound into
  the RTP stream, it tells every client which sound was played and each one
  fetches the CDN object itself, so the effect is played through the same
  engine the voice-message player uses and only for the channel this client is
  actually sitting in.
- **Blocked by**: GIF
  providers are done: trending, search and suggestions go through Discord's
  own `/gifs/*` proxy — the desktop client never talks to Tenor or Giphy
  directly and neither does this — and a pick is sent as the `gif_src` link
  rather than the `src` preview.

## FBC-VOICE — Voice, video, screen share, calls

- **Bundle evidence**: 15 endpoint constants; native `discord_voice`,
  `discord_krisp`, `discord_media`, `discord_overlay2`.
- **Symbols**: `VOICE_STATE_UPDATE`, `VOICE_SERVER_UPDATE`, `CALL_CREATE`,
  `STREAM_CREATE`, `GUILD_RING_START`, and 14 more.
- **Purpose**: voice rooms, direct calls, video, screen sharing, Go Live.
- **UI surface**: voice room grid, call strip, Go Live control with viewer count, stream viewer.
- **Contract**: opcode 4 voice state, Voice Gateway v8, UDP discovery, DAVE
  MLS, RTP v2.
- **Dependencies**: FBC-GATEWAY, FBC-GUILD, FBC-CHANNEL.
- **Status**: **Partial** — audio is implemented for the desktop-user
  transport; video and screen share are not.
- **Implemented**: Voice Gateway v8, DAVE, AES-256-GCM and
  XChaCha20-Poly1305 transport encryption, Opus capture/playback, participant
  roster, guild voice and DM/group calls over the desktop-user session. Who is
  already seated is read from `READY_SUPPLEMENTAL.guilds[].voice_states` — the
  only place a user account is told, `GUILD_CREATE` being the bot path — and
  shown under every voice channel in the sidebar. DAVE is not a precondition:
  the identify carries `max_dave_protocol_version: 0` when secure frames are
  unavailable, which is what the desktop client itself sends, and the room runs
  on the transport cipher. A microphone that will not open no longer refuses
  the join; the room is still joined to listen and says the uplink is silent.
  A live connection stays reachable from the sidebar after navigating away.
- **Tests**: `discord_voice_*_test.dart`, `discord_rtp_*_test.dart`,
  `voice_controller_test.dart`, `voice_connection_bar_test.dart`,
  `discord_voice_state_roster_test.dart`, `dm_call_workflow_test.dart`.
- **Live evidence**: an account reported Flucord's join appearing in the real
  client's voice channel; audio interoperability itself is still unverified.
  Go Live's signalling half is implemented: opcodes 18-22 and the four
  `STREAM_*` dispatches, with the composed stream key
  (`guild:<guild>:<channel>:<user>` or `call:<channel>:<user>`) built locally
  at start because every later frame carries it back, and the RTC endpoint
  tracked apart from the stream since Discord assigns it afterwards and
  reassigns it on a region change.
  Encoding is implemented natively. `libwebrtc.dll` does contain VP8, VP9 and
  H.264 encoders, but `flutter_webrtc` ships no headers, no import library and
  no encoded-frame callback, so none of it is reachable from this process.
  `windows/flucord_video` uses what Windows itself provides instead: Desktop
  Duplication for capture, the H.264 encoder MFT for compression, BGRA to NV12
  converted in between. Frame buffers are handed to the callee rather than
  borrowed, because a Dart native callback is delivered asynchronously and the
  capture thread has released the surface by then.
- **Live evidence**: the encoder was run against this machine's displays on
  `2026-07-28` — 359 frames in five seconds at 15fps, 24 keyframes, 1.39 MB of
  Annex B, each access unit starting `00 00 00 01`.
  The frames are packetised for RTP as RFC 6184 defines it: single NAL units
  where they fit, FU-A fragments where they do not, both start-code lengths
  recognised because the encoder uses both, and the marker only on the last
  payload of an access unit.
  A depacketiser reverses all of it, so the sender can be checked against
  itself, and a decode probe runs the result through the system H.264 decoder
  MFT — the same decoder a Discord client on Windows draws with.
  Packets are then built into RTP frames on payload type 101 — not the voice
  connection's 0x78, which a receiver would decode as Opus and discard — and
  handed to the transport that encrypts and sends them.
- **Live evidence**: run against this machine's displays on `2026-07-28` —
  556 captured frames became 2144 RTP packets, 1038 of them fragments, none
  over the payload budget; all 556 access units came back with every NAL byte
  for byte, and the system decoder produced 556 pictures from them. A second
  run with the transport cipher in place encrypted all 1314 packets of 171
  frames with AES-256-GCM, 1.2 MB, with no transport error.
  The receiving half is implemented too: a native H.264 decoder with an
  NV12-to-BGRA conversion behind it, and a viewer widget that draws the
  pictures. That is both a feature — watching somebody else's share — and the
  only way this machine can exercise the sending half end to end, since the
  stream it produces is decoded back in-process exactly as a watching client
  would.
- **Blocked by**: a second Discord account is the only thing that can show the
  picture arriving over Discord's own servers rather than through a local
  loop. A stream's audio also still rides the voice connection rather than the
  stream's own.

## FBC-STAGE — Stage channels

- **Symbols**: `STAGE_INSTANCE_CREATE`/`UPDATE`/`DELETE`.
- **Purpose**: stage discovery, speaker requests, moderation.
- **UI surface**: the stage controls above the voice connection bar.
- **Contract**: `POST /stage-instances`, `GET /guild-stages`.
- **Dependencies**: FBC-VOICE.
- **Status**: **Partial**.
- **Implemented**: channel type 13 is recognised rather than flattened into
  ordinary voice; the live instance and its topic are read from
  `STAGE_INSTANCE_*` and from the `stage_instances` a `GUILD_CREATE` or
  `READY_SUPPLEMENTAL` carries, which is the only notice of a stage that
  started before this client connected. The audience side of participation
  works over `PATCH /guilds/{id}/voice-states/@me`: request to speak, withdraw,
  accept an invitation, step back down.
- **Tests**: `stage_channel_test.dart`, `stage_controls_widget_test.dart`.
- **Moderation**: starting, renaming and ending an instance, and moving
  anybody on or off the stage, all through
  `POST`/`PATCH`/`DELETE /stage-instances` and
  `PATCH /guilds/{id}/voice-states/{userId}`. Being a stage moderator is three
  permissions held together — MANAGE_CHANNELS, MUTE_MEMBERS, MOVE_MEMBERS —
  and the controls are withheld unless all three are.
- **Live evidence**: none.
- **Blocked by**: nothing outstanding for the desktop-user session; stage
  discovery listings and scheduled-event-linked stages are separate surfaces.

## FBC-EVENTS — Guild scheduled events

- **Symbols**: `GUILD_SCHEDULED_EVENT_CREATE`/`UPDATE`/`DELETE`,
  `GUILD_SCHEDULED_EVENT_USER_ADD`/`REMOVE`, and 4 exception events.
- **Purpose**: event calendar, RSVP, recurrence exceptions.
- **UI surface**: server Events surface.
- **Contract**: `GET /guilds/{id}/scheduled-events?with_user_count=true`,
  `PUT`/`DELETE /guilds/{id}/scheduled-events/{event}[/{exception}]/users/@me`,
  `POST /guilds/{id}/scheduled-events`,
  `PATCH`/`DELETE /guilds/{id}/scheduled-events/{event}`,
  `GET /guilds/{id}/scheduled-events/{event}/users?with_member=true`.
- **Dependencies**: FBC-GUILD.
- **Status**: **Partial**.
- **Implemented**: event loading, SQLite v16 persistence, live create/update/
  delete and subscriber dispatches, navigation into voice and stage channels.
  RSVP: the desktop-user transport now reads a guild's events with their
  interested counts and says whether this account is interested. Discord
  carries both answers on one route — a `PUT` with its own response value, and
  a `DELETE` with no body — and one occurrence of a recurring event names
  itself in the path. The count is left to the dispatch that moves it rather
  than patched locally, since two places counting the same thing is how a
  count ends up permanently wrong by one. An event that has ended refuses the
  request, and the control reads that as a refusal rather than as a fault.
  Events are also created, edited and deleted, gated on Manage Events — the
  affordance is withheld rather than the request, so an account without it
  sees the list and none of the controls. A create sends the whole event
  because Discord takes one; an edit sends only what moved, and an edit that
  moved nothing closes instead of recording a change nobody made. Deleting
  asks first, since it cannot be undone from here, and cancelling an event is
  deliberately a different call: a status change, not a delete.
  Who is interested is read on demand rather than with the list — a server
  with twenty events would otherwise make twenty requests to draw a panel
  nobody has asked anything of yet — and names people by the nickname their
  server knows them by, because that is the name everybody else there sees.
  An event carries a cover, chosen through the same picker the profile uses.
  The edit tells an untouched cover from a cleared one — collapsing the two
  would drop somebody's picture every time they renamed an event — and a CDN
  hash is refused where a picture was asked for, since sending Discord back
  the name it gave us asks it to store its own filename as an image.
  An event repeats daily, weekly, monthly or yearly, or not at all. Discord
  replaces the whole rule on every write, so the parts this build shows no
  control for — the second Tuesday of the month, a list of months, a day of
  the year — are carried through untouched: editing when an event repeats must
  not quietly rewrite the rest of when it happens. The three frequencies
  Discord never offers a guild event are absent rather than listed and
  refused, because a choice nobody can make is not a choice.
  All four exception dispatches are handled: an occurrence moved or called off
  is folded into the event it belongs to, a revised one replaces the one it is
  for rather than joining it, and the plural delete puts a whole series back
  to its rule. An exception for an event this session has never read is
  dropped rather than turned into a row, since inventing one would show an
  event with no name to somebody who never asked for it.
- **Tests**: `discord_chat_repository_scheduled_events_test.dart`,
  `discord_scheduled_event_mapper_test.dart`,
  `scheduled_event_rsvp_test.dart`,
  `scheduled_event_rsvp_repository_test.dart`,
  `guild_event_editing_test.dart`.
- **Live evidence**: none for the desktop-user transport.
- **Blocked by**: nothing outstanding for the desktop-user session. Live
  evidence is still missing: the routes and dispatches are exercised against
  fixtures, not against a real guild.

## FBC-APPLICATION — Bots, commands, interactions, activities

- **Bundle evidence**: 70 endpoint constants across 15 segments.
- **Symbols**: `INTERACTION_CREATE`/`SUCCESS`/`FAILURE`,
  `INTERACTION_MODAL_CREATE`, `APPLICATION_COMMAND_*`, `ACTIVITY_START`,
  and 8 more.
- **Purpose**: slash commands, message components, modals, embedded activities.
- **UI surface**: the command list under the composer, and the option form.
- **Contract**: `GET /channels/{id}/application-commands/search`,
  `POST /interactions`.
- **Dependencies**: FBC-GATEWAY, FBC-CHANNEL, FBC-MESSAGE.
- **Status**: **Partial**.
- **Implemented**: chat-input commands are listed per channel, filtered as the
  composer is typed past the slash, and run as a type-2 interaction. A user
  session invokes by echoing the whole command object back inside `data`
  rather than naming it by id, so the search result is kept verbatim — a
  re-serialised command would differ from what Discord sent and be refused —
  and the `version` field is required for the same reason. The interaction
  names the gateway session, read live because a reconnect replaces it, and
  carries a per-invocation nonce. Required options are collected before the
  call, since Discord refuses an incomplete one with nothing on screen to
  explain it. Application-command mentions still render as static text; the
  Social SDK activity-invite and lobby-call path is separate.
- **Tests**: `slash_command_test.dart`, `slash_command_widget_test.dart`,
  `social_sdk_activity_*_test.dart` for the SDK path.
- **Live evidence**: none.
  Message components are rendered and pressed: buttons and string selects go
  out as type-3 interactions carrying the message id and flags, and an
  `INTERACTION_MODAL_CREATE` opens a form whose submission is type 5 reusing
  the nonce the modal was opened with. The component tree is walked rather
  than read two deep, because Components V2 nests action rows inside
  containers. A link button sends nothing — it is a hyperlink.
  Context-menu commands are listed and run on a target: the two kinds are the
  same type-2 interaction as a slash command, distinguished by carrying a
  `target_id` instead of options, and the kind being asked for travels in the
  search query. The directory selects — user, role, channel, mentionable —
  carry a type and no options, so the picker offers the workspace's own
  members, roles and channels.
- **Blocked by**: embedded activities are a separate transport, and a
  premium-button component (style 6) resolves to a purchase flow this client
  has no surface for.

## FBC-OAUTH — OAuth2, connections, integrations, invites, webhooks

- **Bundle evidence**: 36 endpoint constants across 7 segments.
- **Symbols**: `OAUTH2_TOKEN_CREATE`/`DELETE`/`REVOKE`,
  `USER_CONNECTIONS_UPDATE`, `INTEGRATION_CREATE`/`DELETE`,
  `WEBHOOKS_UPDATE`, and 3 more.
- **Purpose**: authorized applications, third-party connections, invites.
- **UI surface**: Connections, account home.
- **Contract**: documented public OAuth2 endpoints only.
- **Dependencies**: none.
- **Status**: **Implemented** for the documented public OAuth2 surface.
- **Implemented**: native PKCE S256 public-client flow, `flucord://` callback,
  refresh rotation, separate grant vault, `identify`, `guilds`,
  `guilds.members.read`, `connections`.
- **Tests**: `discord_oauth_*_test.dart`, `oauth_guild_*_test.dart`.
- **Live evidence**: OAuth authorization and refresh validated on Windows.
- **Blocked by**: nothing. Undocumented user-session OAuth management routes
  are deliberately excluded from this domain.

## FBC-MODERATION — Reporting, safety, AutoMod, bans

- **Bundle evidence**: 39 endpoint constants across 9 segments.
- **Symbols**: `GUILD_BAN_ADD`/`REMOVE`, `GUILD_BULK_BAN_UPDATE`,
  `GUILD_PRUNE_UPDATE`, `AUTO_MODERATION_MENTION_RAID_DETECTION`,
  `USER_REQUIRED_ACTION_UPDATE`.
- **Purpose**: reporting flows, AutoMod, bans, family centre.
- **UI surface**: the moderation and AutoMod sections of guild settings; the
  report control on a message, a member and a server; the Account Standing
  page and the Family Center page in user settings.
- **Contract**: `POST /reporting/{type}`, `PUT /guilds/{id}/bans/{user}`,
  `GET`/`POST`/`PATCH`/`DELETE /guilds/{id}/auto-moderation/rules`,
  `POST /guilds/{id}/auto-moderation/rules/validate`,
  `POST /guilds/{id}/auto-moderation/clear-mention-raid`,
  `POST /guilds/{id}/auto-moderation/false-alarm`,
  `POST /guilds/{id}/auto-moderation/alert-action`,
  `GET /safety-hub/@me`, `POST /safety-hub/request-review/{id}`,
  `GET /family-center/@me`, `POST /family-center/@me/link-code`.
- **Dependencies**: FBC-GUILD.
- **Status**: **Partial**.
- **Implemented**: the ban list, ban search, banning and unbanning, kicking a
  member, and the audit log. Each control is withheld unless the account holds
  the permission for it rather than offered and then refused by the server.
  AutoMod rules are listed, created, edited, switched off and deleted, gated
  on Manage Server. Every trigger and action code the bundle names is read,
  including the ones this build has no form for, so a rule created elsewhere
  survives an edit of its name rather than being rewritten. A draft is checked
  against `/rules/validate` before it is created, because the regexes compile
  server-side and asking is the only honest check; a refusal that is not a 400
  is reported as a failure rather than as a verdict on the rule. Discord's own
  word lists are picked as checkboxes, since their contents are server-side and
  never reach a client, and a rule of any kind can be told which roles and
  channels to skip. Exemptions are compared as sets, so reopening a rule and
  saving it untouched sends nothing. Mention rules carry raid protection as a
  switch of its own, since a raid is many members each staying under the
  per-message limit. The two raid controls — clear the alert, report a false
  alarm — sit on the same page. On the alert AutoMod posts, a moderator can
  mark it handled, reopen it, delete the message that tripped the rule, or
  report the rule as wrong; the controls appear only on a type-24 message and
  only with Manage Messages, which is the check Discord makes.
  Reporting walks the menu graph Discord serves per report type and submits
  the answers back; it is raised from a message, a member or a whole server,
  and is never sent without an explicit action. A first DM from somebody not
  yet written to is reported under its own type, because Discord serves a
  different menu for it.
  Account standing reads what Discord has on record — records against the
  account and against servers it owns, shown apart — and asks for a record to
  be looked at again where that is allowed. Discord's numeric standing is
  carried but deliberately not translated into named tiers: the bundle ships
  no enum for it that static analysis recovers, and telling somebody their
  account is "limited" on a guessed mapping would be worse than showing the
  records and letting them speak. A record Discord declines to reopen reads as
  an answer rather than as an error.
  The family centre lists the accounts linked to this one and the activity
  summary Discord reports about a linked teenager — counts only, which is all
  the route carries, and the page says so rather than leaving a parent to
  wonder whether it is showing messages. A link code is minted only when asked
  for and dropped when the page closes, because it grants a parent a view of
  the account. Discord's age group is shown verbatim: renaming it would be
  answering a legal question this client has no standing to answer.
- **Tests**: `guild_management_repository_bans_cases.dart`,
  `guild_management_repository_automod_cases.dart`,
  `guild_admin_capabilities_test.dart`, `guild_settings_widget_test.dart`,
  `automod_rule_test.dart`, `automod_description_test.dart`,
  `automod_section_widget_test.dart`, `automod_fields_widget_test.dart`,
  `automod_alert_action_test.dart`, `automod_alert_widget_test.dart`,
  `report_dialog_widget_test.dart`, `report_targets_test.dart`,
  `account_standing_test.dart`, `account_standing_widget_test.dart`,
  `family_centre_test.dart`, `family_centre_widget_test.dart`.
- **Live evidence**: none.
- **Blocked by**: the suspended-account routes, and the family-centre controls
  that act on a linked teenager's settings — restricted schedules, consents,
  the teen settings proto. A suspended session cannot be exercised without
  suspending an account, which is not something to arrange deliberately, and
  the teen controls need a second, linked account to act on. AutoMod itself has no route left unused: the incident-actions and
  report-raid routes belong to the raid-alert domain rather than to AutoMod
  rules.

## FBC-AI — Conversation summaries and text tools

- **Bundle evidence**: 5 endpoint constants under `ai`.
- **Symbols**: `CONVERSATION_SUMMARY_UPDATE`.
- **Purpose**: thread summaries, translation, grammar, titles.
- **UI surface**: none yet; the store is in place for one.
- **Contract**: `CONVERSATION_SUMMARY_UPDATE`, `POST /ai/summarize-thread/{id}`,
  `/ai/translate`.
- **Dependencies**: FBC-MESSAGE.
- **Status**: **Partial**.
- **Implemented**: summaries are read from the dispatch that carries them and
  held per channel — merged rather than replaced, since a dispatch names only
  what changed; ordered by the message each stretch starts at, so a late
  dispatch about an old stretch lands where that stretch is; capped at the 75
  the desktop client keeps; and a summary Discord has not written yet is
  dropped rather than shown as a blank card.
- **Tests**: `conversation_summary_test.dart`.
- **Live evidence**: none.
- **Blocked by**: server-side gating — whether an account receives summaries
  at all is an experiment, and the `/ai/*` routes that ask for one on demand
  are refused without it. Translation and grammar tools are untouched.

## FBC-PLATFORM — Experiments, telemetry, changelogs, client shell

- **Bundle evidence**: 37 endpoint constants across 22 segments.
- **Symbols**: `EXPERIMENT_SESSION_OVERRIDE_CREATE`/`DELETE`,
  `CONTENT_INVENTORY_INBOX_STALE`.
- **Purpose**: experiment assignment, telemetry, changelogs, deep links.
- **UI surface**: application shell, tray, updater, deep links.
- **Contract**: `GET /experiments`, `POST /science`.
- **Dependencies**: none.
- **Status**: **Partial**.
- **Implemented**: `/experiments` is fetched during remote auth to retain
  Discord's fingerprint. Flucord deliberately sends no `/science` telemetry.
- **Tests**: `desktop_protocol_router_test.dart`, `desktop_packaging_test.dart`.
- **Live evidence**: `/experiments` fetch validated on Windows `2026-07-25`.
- **Blocked by**: **server-side experiments are not implementable.** Guild and
  user treatment assignments are computed by Discord and returned per account;
  a bundle snapshot proves only that the client reads them. No experiment is
  ever reported as an implemented Flucord feature.

## FBC-NATIVE — Native desktop modules

- **Bundle evidence**: 17 installed modules — `discord_cloudsync`,
  `discord_desktop_core`, `discord_desktop_overlay`, `discord_dispatch`,
  `discord_erlpack`, `discord_game_utils`, `discord_hook`, `discord_krisp`,
  `discord_media`, `discord_modules`, `discord_notifications`,
  `discord_overlay2`, `discord_rpc`, `discord_spellcheck`, `discord_utils`,
  `discord_voice`, `discord_zstd`.
- **Purpose**: platform integration the renderer cannot provide.
- **UI surface**: tray, notifications, updater, overlay, spell check.
- **Contract**: Electron native `.node` add-ons. Flucord reimplements the
  behaviour in Dart and C++ and links none of Discord's binaries.
- **Dependencies**: none.
- **Status**: **Partial**.
- **Implemented**: notifications, tray, deep links, single instance, updater,
  media playback, audio capture, Opus, credential vault — all independently.
- **Tests**: `desktop_*_test.dart`, `native_media_*_test.dart`.
- **Live evidence**: Windows release build and smoke run.
- **Blocked by**: `discord_zstd` has no Flucord equivalent (see FBC-GATEWAY);
  `discord_hook`/`discord_overlay2` (in-game overlay) and `discord_krisp`
  (noise suppression) have no equivalent. Neither Discord binary may be
  redistributed, so each needs an independent implementation.

## FBC-COMMERCE — Nitro, store, gifts, quests, collectibles

- **Bundle evidence**: 124 endpoint constants across 28 segments; 26 dispatch
  events including `ENTITLEMENT_*`, `PAYMENT_UPDATE`, `WALLET_BALANCE_UPDATE`.
- **Status**: **Not applicable**.
- **Reason**: purchase, payout, and gift-redemption flows run through Discord's
  payment provider session and PCI-scoped browser surfaces. Flucord will not
  proxy another party's billing credentials, and no independent implementation
  can complete these flows. Read-only entitlement display is tracked as a
  future FBC-PROFILE item rather than as commerce parity.

## FBC-GAMES — Game library, game servers, console, social layer

- **Bundle evidence**: 33 endpoint constants across 7 segments; 9 dispatch
  events including `GAME_SERVER_*`, `LIBRARY_APPLICATION_UPDATE`, `HAVEN_*`.
- **Status**: **Not applicable**.
- **Reason**: the game library and installer depend on `discord_dispatch`, a
  proprietary distribution client, and the social layer requires the separately
  approved Discord Social SDK package. Flucord already implements the approved
  Social SDK surface under FBC-RELATIONSHIPS; the remainder cannot be
  reimplemented without redistributing Discord's binaries.

---

## Next dependency-first slices

1. **FBC-GUILD member panel.** The lazy member-list transport and row state
   machine have landed; what remains is the controller and sidebar cut that
   drives range subscriptions from the panel's scroll position and renders the
   server-authoritative groups.
2. **FBC-READSTATE notification centre.** `NOTIFICATION_CENTER_*` and message
   requests are the two read-state types still unmodelled; R04 lists the REST
   bodies for the notification-centre acks as unestablished, so this one needs
   a fresh corpus pass before it can be built.
3. **FBC-GATEWAY versioned `client_state`.** `read_state_version` and
   `user_guild_settings_version` are now echoed, because the read-state store
   can apply a `partial: true` delta for both. `highest_last_message_id` and
   `private_channels_version` are computed but deliberately not sent: guild and
   private-channel hydration still replaces whatever `READY` carries, and R09
   lists the server-side effect of `private_channels_version` as
   unestablished.

## Legal boundary

The snapshot is an implementation input. Discord's private desktop protocol may
change without notice, and matching its build profile or headers establishes
neither protocol stability nor account-enforcement outcomes. No Discord source,
asset, string table, token, or storage is copied into this repository.
