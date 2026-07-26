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
| Renderer entry chunk | `web.b8b5ddfa0f88ae29.js` |
| Renderer chunks analyzed | 4,614 |
| Renderer corpus bytes | 157,588,028 |
| Endpoint constants | 949 |
| Endpoint path segments | 165 |
| Gateway dispatch events | 175 |
| Native desktop modules | 17 |

## Coverage

| Metric | Value | Definition |
| --- | --- | --- |
| Discovery coverage | **100.00%** | classified segments and events / discovered segments and events (340/340) |
| Implementation coverage | **10.53%** | applicable domains verified complete / applicable domains (2/19) |
| Partial domains | 12 of 19 applicable | at least one vertical slice shipped, remainder open |
| Automated test coverage | 84.13% lines | `flutter test --coverage`, 656 passing, 6 skipped |

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

- **Bundle evidence**: `web.b8b5ddfa0f88ae29.js` socket module; native
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
- **UI surface**: Connections, QR login dialog, hCaptcha challenge window.
- **Contract**: remote-auth Gateway v2, `POST /users/@me/remote-auth/login`,
  `X-Captcha-Key`/`X-Captcha-Rqtoken`/`X-Captcha-Session-Id`.
- **Dependencies**: FBC-GATEWAY.
- **Status**: **Partial**.
- **Implemented**: RSA-2048 QR remote auth, mandatory hCaptcha through an
  ephemeral system WebView2, versioned operating-system session vault.
- **Tests**: `discord_remote_auth_gateway_test.dart`,
  `discord_desktop_login_controller_test.dart`.
- **Live evidence**: phone approval, hCaptcha completion, encrypted session
  exchange, and restart restoration validated on Windows `2026-07-25`.
- **Blocked by**: authenticator management, age verification, account standing,
  and session revocation have no vertical slice.

## FBC-PROFILE — Current user, other users, user settings

- **Bundle evidence**: 213 endpoint constants across `users`, `settings`,
  `unique-username`, `badge-icons`.
- **Symbols**: `USER_UPDATE`, `USER_NOTE_UPDATE`, `USER_BADGE_STATE_UPDATE`,
  `USER_SETTINGS_PROTO_UPDATE`.
- **Purpose**: identity, profile cards, client settings synchronization.
- **UI surface**: account panel, member and friend profile popovers.
- **Contract**: `GET /users/@me`, `GET /users/{id}/profile`,
  `PATCH /users/@me/settings-proto/{n}`.
- **Dependencies**: FBC-GATEWAY.
- **Status**: **Partial**.
- **Implemented**: `READY` identity projection, guild member profile popover,
  OAuth `identify` profile header.
- **Tests**: `discord_oauth_account_mapper_test.dart`, `widget_test.dart`.
- **Live evidence**: authenticated identity hydrated on Windows `2026-07-25`.
- **Blocked by**: no settings-proto reader/writer, so notification, privacy,
  appearance, and keybind settings are absent.

## FBC-PRESENCE — Presence and typing

- **Symbols**: `PRESENCE_UPDATE`, `PRESENCES_REPLACE`, `TYPING_START`.
- **Purpose**: online state, activities, typing indicators.
- **UI surface**: member list, profile popovers, typing row.
- **Contract**: Gateway dispatches; opcode 37 `activities` subscription.
- **Dependencies**: FBC-GATEWAY, FBC-GUILD.
- **Status**: **Partial**.
- **Implemented**: live presence and typing dispatch handling with expiry and
  throttling.
- **Tests**: `discord_repository_events_test.dart`, `widget_test.dart`.
- **Live evidence**: none for the desktop-user transport.
- **Blocked by**: `PRESENCES_REPLACE` and lazy member-list presence require
  FBC-GUILD member lists first.

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
- **Blocked by**: the controller and member-panel cut. The roster is parsed and
  cached but not yet projected into the sidebar, so the panel still groups a
  flat member list locally. `GET /guilds/{id}/members` enumeration and
  `GUILD_MEMBERS_CHUNK` remain unimplemented.

> Correction, `2026-07-26`: an earlier revision of this row named opcode 14 as
> the member-list contract. Static analysis of `web.b8b5ddfa0f88ae29.js` finds
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
  `GET /channels/{id}/threads/archived/public`, forum thread creation.
- **Dependencies**: FBC-GATEWAY, FBC-GUILD.
- **Status**: **Partial**.
- **Implemented**: categories, positions, collapsible sidebar, active and
  archived threads, forum/media posts with tags, layouts, and attachments.
- **Tests**: `discord_chat_repository_threads_test.dart`,
  `discord_chat_repository_forums_test.dart`, `widget_test.dart`.
- **Live evidence**: channel history on Windows `2026-07-25`.
- **Blocked by**: thread member lists and channel permission overwrites.

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
- **Implemented**: local unread and mention state, first-unread anchors, Inbox,
  mark-all-read, native desktop notifications.
- **Tests**: `unread_state_test.dart`, `inbox_controller_test.dart`.
- **Live evidence**: none for server-side acknowledgement.
- **Blocked by**: server read state is never fetched or acknowledged, so unread
  state does not survive a reinstall or sync with the official client.

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
  searchable pickers, inline custom-emoji rendering.
- **Tests**: `discord_chat_repository_emojis_test.dart`,
  `discord_chat_repository_stickers_test.dart`.
- **Live evidence**: none for the desktop-user transport.
- **Blocked by**: soundboard needs FBC-VOICE; GIF providers need a media proxy.

## FBC-VOICE — Voice, video, screen share, calls

- **Bundle evidence**: 15 endpoint constants; native `discord_voice`,
  `discord_krisp`, `discord_media`, `discord_overlay2`.
- **Symbols**: `VOICE_STATE_UPDATE`, `VOICE_SERVER_UPDATE`, `CALL_CREATE`,
  `STREAM_CREATE`, `GUILD_RING_START`, and 14 more.
- **Purpose**: voice rooms, direct calls, video, screen sharing, Go Live.
- **UI surface**: voice room grid, call strip, screen picker.
- **Contract**: opcode 4 voice state, Voice Gateway v8, UDP discovery, DAVE
  MLS, RTP v2.
- **Dependencies**: FBC-GATEWAY, FBC-GUILD, FBC-CHANNEL.
- **Status**: **Absent** for the desktop-user transport.
- **Implemented**: a separate Bot-transport voice stack exists — Voice Gateway
  v8, DAVE, AES-256-GCM and XChaCha20-Poly1305 transport encryption, Opus
  capture/playback, participant roster.
- **Tests**: `discord_voice_*_test.dart`, `discord_rtp_*_test.dart`.
- **Live evidence**: none; interoperability in a real session is unverified.
- **Blocked by**: the desktop-user session has never been wired to the voice
  signalling service, and video plus screen share have no encoder path.

## FBC-STAGE — Stage channels

- **Symbols**: `STAGE_INSTANCE_CREATE`/`UPDATE`/`DELETE`.
- **Purpose**: stage discovery, speaker requests, moderation.
- **UI surface**: none.
- **Contract**: `POST /stage-instances`, `GET /guild-stages`.
- **Dependencies**: FBC-VOICE.
- **Status**: **Absent**.
- **Implemented**: stage channels appear in the sidebar and in scheduled-event
  navigation only.
- **Tests**: none specific.
- **Live evidence**: none.
- **Blocked by**: FBC-VOICE.

## FBC-EVENTS — Guild scheduled events

- **Symbols**: `GUILD_SCHEDULED_EVENT_CREATE`/`UPDATE`/`DELETE`,
  `GUILD_SCHEDULED_EVENT_USER_ADD`/`REMOVE`, and 4 exception events.
- **Purpose**: event calendar, RSVP, recurrence exceptions.
- **UI surface**: server Events surface.
- **Contract**: `GET /guilds/{id}/scheduled-events?with_user_count=true`.
- **Dependencies**: FBC-GUILD.
- **Status**: **Partial**.
- **Implemented**: event loading, SQLite v16 persistence, live create/update/
  delete and subscriber dispatches, navigation into voice and stage channels.
- **Tests**: `discord_chat_repository_scheduled_events_test.dart`,
  `discord_scheduled_event_mapper_test.dart`.
- **Live evidence**: none for the desktop-user transport.
- **Blocked by**: RSVP mutation and the four recurrence-exception dispatches.

## FBC-APPLICATION — Bots, commands, interactions, activities

- **Bundle evidence**: 70 endpoint constants across 15 segments.
- **Symbols**: `INTERACTION_CREATE`/`SUCCESS`/`FAILURE`,
  `INTERACTION_MODAL_CREATE`, `APPLICATION_COMMAND_*`, `ACTIVITY_START`,
  and 8 more.
- **Purpose**: slash commands, message components, modals, embedded activities.
- **UI surface**: none for the desktop-user transport.
- **Contract**: `GET /channels/{id}/application-commands/search`,
  `POST /interactions`.
- **Dependencies**: FBC-GATEWAY, FBC-CHANNEL, FBC-MESSAGE.
- **Status**: **Absent**.
- **Implemented**: application-command mentions render as static text; the
  Social SDK activity-invite and lobby-call path is separate.
- **Tests**: `social_sdk_activity_*_test.dart` for the SDK path only.
- **Live evidence**: none.
- **Blocked by**: no interaction transport, no component or modal renderer.

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
- **UI surface**: none.
- **Contract**: `POST /reporting/{type}`, `PUT /guilds/{id}/bans/{user}`.
- **Dependencies**: FBC-GUILD.
- **Status**: **Absent**.
- **Tests**: none.
- **Live evidence**: none.
- **Blocked by**: no moderation surface exists yet. Reporting endpoints will
  only ever be called from an explicit user action.

## FBC-AI — Conversation summaries and text tools

- **Bundle evidence**: 5 endpoint constants under `ai`.
- **Symbols**: `CONVERSATION_SUMMARY_UPDATE`.
- **Purpose**: thread summaries, translation, grammar, titles.
- **UI surface**: none.
- **Contract**: `POST /ai/summarize-thread/{id}`, `/ai/translate`.
- **Dependencies**: FBC-MESSAGE.
- **Status**: **Absent**.
- **Tests**: none.
- **Live evidence**: none.
- **Blocked by**: server-side gating. Availability is decided by Discord
  experiments per account and cannot be verified from the bundle alone.

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
   server-authoritative groups. This also unblocks FBC-PRESENCE, because a
   member-list item is where the desktop transport first sees presence.
2. **FBC-READSTATE server acknowledgement.** Unread state currently never
   leaves the machine, so it cannot survive a reinstall or agree with the
   official client.
3. **FBC-GATEWAY versioned `client_state`.** Echoing the cache versions Discord
   sends would replace full-mode `READY` guilds with partial updates, which is
   the difference between re-downloading every guild on each connect and
   applying a delta.

## Legal boundary

The snapshot is an implementation input. Discord's private desktop protocol may
change without notice, and matching its build profile or headers establishes
neither protocol stability nor account-enforcement outcomes. No Discord source,
asset, string table, token, or storage is copied into this repository.
