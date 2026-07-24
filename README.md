# Flucord

Flucord is a native Flutter desktop messaging client for Windows, macOS, and
Linux. The Windows release is verified locally; macOS and Linux runners are
configured but still require release verification on their native hosts. It
provides server and ordered channel navigation with collapsible categories,
searchable message history, replies, attachments, reactions, message editing
and deletion, native message forwarding, native message polls,
active-thread discovery and creation,
archived-thread browsing,
native forum and media-channel feeds, member roles and presence, local unread
markers, paginated pinned messages, native desktop notifications,
cross-platform tray lifecycle, channel deep links,
signed updates, native voice-device diagnostics, desktop capture preview,
native voice-message recording and waveform playback,
documented Discord CDN guild/member identity, anchored member profile
popovers, a global native Quick Switcher, a cross-server Inbox, and theme
switching without a browser runtime. The composer includes a searchable native
Unicode and guild-emoji picker plus caret-aware member, role, and channel
autocomplete. Local unread bursts open at a Discord-like NEW
boundary in the message timeline. Discord rich
embeds retain their documented structured fields across live updates and
offline cache restores. Video attachments and embed video metadata play
through a native Windows texture.

Production startup never substitutes synthetic servers for Discord state. It
restores a supported saved session automatically; without one, Flucord shows an
explicit disconnected workspace. The deterministic `MockChatRepository` is
available only through `FlucordApp.demo()` for tests and deliberate demos.
Bot chat remains an optional, clearly labelled transport rather than a normal
user-account login.

Message bodies, pinned previews, and embed text render GitHub-flavored
Markdown plus Discord's documented user, role, and channel mentions, custom
emoji, localized timestamps, application commands, and tap-to-reveal spoilers.
Channel mentions navigate inside Flucord. Web links open through the native OS
launcher only for `http` and `https` schemes; Markdown never introduces an
embedded browser surface.

Every remote file, image, video, and audio attachment exposes the same compact
native Save As control. Downloads stream through Dart IO with live determinate
or indeterminate progress and explicit cancellation. Flucord writes a sibling
`.part` file first, preserves an existing destination until the response is
complete, and performs the final replacement only after byte-count validation;
failures remain retryable on the attachment without leaving partial files.

Image attachments open in a native browser-free lightbox that preserves the
conversation behind it. The viewer supports mouse/trackpad pan and zoom,
toolbar zoom/reset controls, double-click reset, Ctrl shortcuts, Escape close,
compact-window geometry, loading and error states, and the same shared Save As
transfer state as the message attachment. Messages and forwarded snapshots with
multiple images expose bounded previous/next controls, Left/Right shortcuts,
and a stable position counter without conflicting with image pan gestures.

The composer emoji control opens an anchored native picker, searches common
Unicode shortcodes and the selected server's documented custom emoji, and
inserts the result at the current caret or selection. Guild emoji load through
`GET /guilds/{guild.id}/emojis`; `GUILD_EMOJIS_UPDATE` atomically replaces the
affected server catalog. Animated custom emoji use Discord's documented
`<a:name:id>` syntax and CDN route without private client headers.

Typing `@` or `#` opens a native menu anchored above the composer and projected
from the currently loaded workspace. It ranks guild members, roles, channels,
and threads without another network request; Direct Messages expose only their
participants. Mouse, Up/Down, Enter, Tab, and Escape preserve text-field focus,
and selection inserts Discord's documented `<@id>`, `<@&id>`, or `<#id>` syntax
at the active caret range.

The same guild-aware catalog powers the message reaction action. Its anchored
picker sends Unicode glyphs or Discord's documented `name:id` custom reaction
key, remains mounted while the pointer crosses from a message hover action into
the overlay, and renders known custom reactions as compact native image glyphs.
Reaction details open from the message action bar or a reaction's secondary
click. A native ledger pages documented User objects through Get Reactions,
keeps normal and super reactions distinct, preserves loaded people across
retryable failures, and retains burst counts/colors in the existing message
cache.

Documented guild sticker catalogs load through REST, replace atomically on
`GUILD_STICKERS_UPDATE`, and persist with their names, tags, availability, and
format metadata. The composer opens a searchable anchored sticker picker and
sends one to three selected IDs through Create Message. PNG, APNG, and GIF
assets render through Flutter's native image codec; Lottie JSON renders through
the native cross-platform Lottie canvas. Both paths keep stable geometry plus
loading and failure states without an embedded browser.

Guild scheduled events load through the documented REST route with subscriber
counts and persist independently in SQLite. The `GUILD_SCHEDULED_EVENT_CREATE`,
`UPDATE`, `DELETE`, `USER_ADD`, and `USER_REMOVE` Gateway dispatches update the
server catalog live. A compact Events entry in the guild channel sidebar opens
a native live/upcoming surface with stable loading, empty, and retry states;
voice and stage events navigate directly to their associated native room while
external events retain their documented location without inventing a private
subscription mutation.

Documented Discord message types and message references survive REST history,
partial Gateway updates, and offline restoration. Native system rows cover
member joins, pins, boosts, thread creation, Stage changes, subscriptions,
Server Discovery changes, and incident reports without presenting them as
ordinary authored chat. Pin rows jump to the referenced message and thread rows
open the referenced native conversation. The same system-event descriptions
feed Inbox previews and desktop notifications.

Channel history loads through Discord's documented `before` cursor in pages
of up to 100 messages. Reaching the top requests the next page while keeping
the visible message anchored. Loaded pages are upserted into SQLite, so the
same cached archive remains browsable in 100-message slices while offline.

The message action bar can start a documented public thread from its source
message. A compact native dialog validates the 1-100 character name, exposes
Discord's 1-hour, 24-hour, 3-day, and 1-week auto-archive durations, and keeps
loading or permission failures in place. The returned channel is persisted,
shown under Active threads, and selected immediately through the existing
history boundary.

Supported default, reply, slash-command, and context-command messages can be
forwarded through Discord's documented message-reference payload. The native
destination dialog searches writable-looking text channels, bot Direct
Messages, and threads while excluding voice, forum, media, and locked archived
destinations. Successful forwards select the destination immediately. Their
immutable message snapshots render inline with the original content,
attachments, embeds, stickers, source channel/server path, and an explicit
fallback for interactive components that cannot be replayed from snapshot
data. Discord does not include an author object in a forwarded snapshot, so
Flucord does not invent one.

The header Threads control keeps active and archived branches in a native
right-side panel. Public archives load through the documented
`GET /channels/{channel.id}/threads/archived/public` route using its ISO8601
`before` cursor and explicit pagination. Selecting any row opens the existing
native timeline. Locked archived threads show their lock state and replace the
composer with a read-only notice; unlocked archives retain Discord's documented
send-to-unarchive behavior. Archived rows stay out of the channel sidebar and
Quick Switcher.

Discord `GUILD_FORUM` and `GUILD_MEDIA` channel types are retained as distinct
native destinations instead of being discarded during bootstrap. Their
guidelines, available tags, default archive duration, sort order, and layout
metadata survive SQLite restoration. Opening one loads active and public
archived posts into a responsive list or gallery feed with tag filters,
loading/error/empty states, and direct thread-timeline navigation. The New Post
dialog uses the documented `POST /channels/{channel.id}/threads` payload with a
nested starter message, up to five applied tags, and Discord's supported
auto-archive durations. The same native file picker used by the message
composer can attach up to ten files to the starter message, including
attachment-only posts, through Discord's multipart payload format.

Forum list layout remains a dense single-column reading surface. Media channels
and channels configured for gallery layout use responsive one- to three-column
cards with real starter-image previews, video/file fallbacks, and stable loading
or broken-image states. Visible cards lazily load missing post history through
the existing repository and SQLite cache without changing the selected channel.

Text-channel messages retain Discord's documented poll question, answers,
expiry, multiselect mode, result counts, and finalized state. The composer opens
a native creation dialog for two to ten answers and durations from one hour to
32 days. Poll-only messages render inline in the timeline and pinned-message
panel with proportional result bars, accessible vote summaries, compact-width
layout, and an End Poll action for polls authored by the connected application.
Gateway poll-vote add/remove events update the cached counts live. Discord does
not document a bot operation for casting a poll vote, so Flucord does not expose
a voting control that would require a private user endpoint.

Standard, reply, attachment, poll-only, and sticker-only sends carry a compact
client nonce with Discord's documented `enforce_nonce` switch, preventing a
retry from creating a duplicate message. A native composer toggle sends without
raising push notifications through `SUPPRESS_NOTIFICATIONS`. Message hover
actions can suppress or restore rich embeds through the documented Edit Message
flags contract while preserving every unrelated and unknown flag bit.

Incoming Discord voice messages retain the documented `IS_VOICE_MESSAGE` flag,
single audio attachment, fractional duration, and base64 waveform. They render
as a compact native player with play/pause, buffering and retry states, elapsed
time, and click-or-drag waveform seeking. Playback uses `media_kit` without a
browser surface. Discord forbids editing voice messages, so Flucord removes the
edit action and rejects the mutation before it reaches the repository. An empty
composer exposes a microphone control that records native 48 kHz stereo PCM,
encodes it with the bundled libopus boundary, packages Ogg/Opus locally, and
uploads the documented duration, waveform, flag, and single audio attachment.
The live waveform row supports cancel and stop-and-send; failed uploads retain
only the recorder-owned temporary file for explicit retry or discard.

An explicitly enabled developer build can also connect through Discord's
documented Bot REST API v10 and Gateway. This transport is disabled and absent
from the normal-account UI by default; it does not accept or emulate personal
account tokens and never represents the linked user identity.
Documented bot Direct Messages can be opened by a recipient's numeric Discord
user ID or directly from an anchored guild-member profile. They then use the
same native history, composer, replies, Markdown, attachments, embeds, and
video surfaces as guild channels. Incoming DM channels are discovered from
Gateway events and restored from the SQLite v7 cache. Member profiles retain
the guild avatar, presence and role context, expose a copyable user ID, dismiss
with Escape or an outside click, and disable messaging the current bot user.

Flucord can separately link a normal Discord identity through the documented
OAuth2 public-client flow. Authorization opens the operating system browser;
the application itself remains native and contains no WebView or browser
runtime. PKCE S256 and a random `state` protect the callback, and the rotating
refresh grant is stored in the operating-system credential vault. The linked
profile, third-party connected-account directory, and paginated server
directory retain documented identity, visibility, icon, banner, ownership,
permission, feature, and approximate member/presence metadata. They remain
separate from the Bot chat session because ordinary OAuth scopes do not grant
friends, channel messages, or user Gateway access.

When no chat transport is active, a restored linked identity now opens its
authorized servers in the main native rail/sidebar workspace instead of hiding
them inside Connections. Server selection, responsive compact layout, linked
identity footer, and owner/admin/member context remain available, while the
channel and message surfaces stay explicitly locked because OAuth does not
provide those resources.

New authorizations also request the documented `guilds.members.read` scope.
On wide layouts, selecting an authorized server loads the current user's server
profile through `/users/@me/guilds/{guild.id}/member` and shows the guild
nickname/avatar, role count, join/boost state, screening, and timeout metadata.
Membership responses are cached per server and never unlock chat resources.
The same native rail exposes an account-home destination. It renders the
documented `/users/@me/connections` result from the `connections` scope with
service, username, verification, visibility, and activity status while keeping
Friends and Direct Messages visibly locked in an ordinary OAuth-only build.
Connected accounts also appear in the Connections settings surface. Older saved
grants may need to be unlinked and linked again to add the new scopes.

The account-home profile header also retains the documented current-user
banner, accent color, legacy discriminator, locale, verification, MFA state,
and public flags returned by `identify`; it does not request the optional email
scope. Discord Friends are not exposed by a public REST route: official access
requires the separately distributed native Discord Social SDK, acceptance of
its terms, and application approval, so Flucord does not fabricate that data.
The Windows runner now exposes a typed `flucord/social_sdk` capability bridge.
An ordinary build reports `sdk_not_bundled`; it never substitutes Bot API data
for relationships. A build with an approved SDK package must configure these
exact CMake cache paths instead of relying on guessed package filenames:

- `FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR`: directory containing
  `discord_partner_sdk/discordpp.h`.
- `FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY`: exact import-library path supplied by
  the downloaded package.
- `FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME`: optional exact runtime-library path to
  install beside `flucord.exe`.

The include directory and import library must be supplied together and are
validated before compilation. They can be provided as CMake cache values or
same-named environment variables.

The Dart side already owns an immutable Social SDK relationship contract for
friends, incoming/outgoing requests, provisional users, spam-request metadata,
and online/idle/do-not-disturb/offline presence. A typed
`getRelationships` platform method maps those values into a native Friends
directory with separate pending, online, offline, loading, empty,
authorization-required, and retry states. The default Windows runner rejects
that method with `sdk_not_bundled`. A package-linked runner performs the native
public-client PKCE flow, exchanges and rotates the SDK grant, waits for
`Client::Status::Ready`, and then maps live `Client::GetRelationships()` data.
Neither path invents data or falls back to Bot API.
The same typed channel now accepts relationship mutations for incoming-request
accept/reject, outgoing-request cancellation, Discord/game friend removal, and
blocking. Actions are gated by the current relationship type, track pending and
failure state per user, and update the visible directory only after the native
operation succeeds. Remove and block require an explicit confirmation. The SDK
callback queue is pumped every 10 ms on the Windows UI thread, and expiring
tokens are refreshed natively. Rotated access and refresh grants are returned
only to a dedicated operating-system credential-vault record; they are not
shared with normal OAuth, Bot transport, SQLite, or logs.

### Enable native Social SDK friends on Windows

1. Obtain the approved Discord Social SDK Windows package for the application
   and enable **Public Client** in its Developer Portal OAuth2 settings.
2. Set the exact package paths for the current PowerShell session:

   ```powershell
   $env:FLUCORD_DISCORD_SOCIAL_SDK_INCLUDE_DIR='C:\sdk\discord-social-sdk\include'
   $env:FLUCORD_DISCORD_SOCIAL_SDK_LIBRARY='C:\sdk\discord-social-sdk\lib\discord_partner_sdk.lib'
   $env:FLUCORD_DISCORD_SOCIAL_SDK_RUNTIME='C:\sdk\discord-social-sdk\bin\discord_partner_sdk.dll'
   ```

3. Run with the same public application ID used by the approved package:

   ```powershell
   flutter run -d windows `
     --dart-define=FLUCORD_DISCORD_CLIENT_ID=123456789012345678
   ```

4. Open Friends and select **Connect Discord**. Flucord uses the SDK's native
   authorization prompt, restores the rotating grant on later starts, and does
   not ask for a personal account token.

## Run

```powershell
flutter pub get
flutter run -d windows
```

On the corresponding native host, use `flutter run -d macos` or
`flutter run -d linux`. Desktop builds are host-specific: Flutter cannot build
a macOS release on Windows or a Linux release on macOS/Windows.

Ubuntu/Debian Linux builds need Flutter's desktop toolchain plus
`libgtk-3-dev`, `libnotify-dev`, `libayatana-appindicator3-dev`, and
`libsecret-1-dev`; `libnotify` delivers native message notifications,
AppIndicator owns the tray menu, and `libsecret` backs credential storage
through the desktop keyring. GNOME also needs its AppIndicator shell extension
enabled. A Secret Service provider such as GNOME Keyring or KWallet must be
available at runtime. Native microphone capture through `record` also requires
the PulseAudio utilities and FFmpeg available to the desktop session.

## Connect a normal Discord account

Enable **Public Client**, register this exact OAuth2 redirect URI, and run with
the public application ID; no client secret is included in the desktop binary:

```text
flucord://oauth/discord/callback
```

```powershell
flutter run -d windows `
  --dart-define=FLUCORD_DISCORD_CLIENT_ID=123456789012345678
```

Open Connections and select **Connect Discord**. OAuth supplies the documented
identity and server directory; the separately approved native Social SDK owns
friends and Direct Messages. See [session transport architecture](docs/SESSION_TRANSPORT.md)
for exact scopes, package setup, boundaries, and developer Bot instructions.

## Optional developer bot transport

Bot REST/Gateway is absent by default. An explicit developer build enables its
separate collapsed panel with `--dart-define=FLUCORD_ENABLE_BOT_TRANSPORT=true`.
It never accepts a personal account token or represents the linked user.

The application layer does not accept an untyped token string. It owns a typed
`DiscordAccountSession`, an explicit capability set, and a domain repository
factory. The current concrete full-chat adapter is
`DiscordBotRepositoryFactory`; documented OAuth user sessions can represent
authorized identity, guild-directory, approved DM-directory, or voice scopes,
but are rejected before IO when a caller requests chat/Gateway capabilities
that those scopes do not provide. See [session transport architecture](docs/SESSION_TRANSPORT.md).

Discord intentionally returns no bot DM inbox through `READY.private_channels`
or `GET /users/@me/channels`. Flucord therefore builds the bot inbox from
proactively opened recipient IDs, live `CHANNEL_CREATE` and `MESSAGE_CREATE`
events, and previously cached channels. This does not expose a normal user's
private Discord inbox or synchronize personal-account DM state.

Discord bots can edit only messages they authored. The UI exposes inline edit
for the connected bot's messages and lets Discord enforce channel-specific
permissions for deletes, uploads, and reactions.

Unread and mention markers are maintained locally for the Flucord installation.
Discord does not publish a bot API for a personal account's read state, so
these markers do not synchronize with the official Discord client. The server
rail aggregates that local state per guild and for Direct Messages: short pips
mark unread spaces, selected spaces retain the taller navigation indicator,
and numeric mention badges are capped visually at `99+`. Each unread burst
also retains its first message ID. Opening the channel clears its counters but
keeps a semantic NEW divider in the timeline until the reader leaves the
channel, backgrounds the app again, or sends a message.

Press `Ctrl+K` anywhere in the ready workspace to open the native Quick
Switcher. It searches servers, bot Direct Messages, text and voice channels,
and active threads by their full destination path. Results remain grouped by
kind, carry local unread and mention indicators, and support arrow keys,
Enter, Escape, mouse selection, and screen-reader semantics. Navigation reuses
the same workspace and history-loading boundary as the server rail and channel
sidebar.

The header Inbox aggregates unread text channels from every guild and cached
bot Direct Message space. Its Unreads tab shows the exact
`Server / #channel` path and local mention count; its Mentions tab retains the
actual messages that mention the connected bot even after their counters are
cleared. Selecting an entry opens the destination and positions the native
timeline at the unread boundary or exact mention message. Mark all as read
clears local channel activity without deleting retained mention history.

Guild icons, global user avatars, guild-specific member avatars, and Discord's
default avatars use documented public CDN routes. Their URLs persist in the
SQLite v4 cache; unavailable images fall back to deterministic initials without
changing navigation, message, member-list, or voice-room geometry.

Rich message embeds preserve author, provider, title, description, fields,
source color, media metadata, footer, and timestamp in the SQLite v5 cache.
Inline fields adapt from three columns to one as the message pane narrows;
failed remote media renders a stable error state instead of collapsing the
conversation. Video attachments and embed video URLs render inline with native
play/pause, mute, seek, duration, fullscreen, loading, retry, and error states.

The SQLite v6 workspace cache also retains Discord role IDs, names, ordering,
and source colors so role mentions remain resolved during offline sessions.
SQLite v7 adds space kinds and DM recipient identity while preserving the
existing guild, role, message, embed, and media records during migration.

SQLite v8 retains documented category channels, child `parent_id` values, and
Discord channel positions. Collapsed categories remain client-only UI state;
selected, unread, and mentioned channels stay visible inside them.

SQLite v9 retains the first local unread message ID separately from unread and
mention counters. A fresh REST bootstrap restores those local activity fields
for matching channels without allowing Gateway metadata updates to erase them.

SQLite v10 retains whether each cached message explicitly mentions the current
bot, allowing the native Inbox to restore exact mention entries offline.

SQLite v11 retains each guild emoji's identity, name, availability, animation
flag, and public CDN URL. Gateway replacements delete stale entries before
writing the current server catalog, so the offline picker cannot resurrect
removed emoji.

SQLite v12 retains thread archive, lock, archive timestamp, and auto-archive
duration metadata. Public archived-thread pages are upserted as they arrive, so
their native timelines and lock state remain available after a restart.

SQLite v13 retains forum/media channel kinds, available tags, post tag IDs,
default archive duration, sort order, and forum layout. Existing text/voice enum
indices remain stable during migration.

SQLite v14 retains each message's complete poll payload, including answer
counts and current-bot vote flags, so result and expiry state survive an offline
restart. Poll-only Inbox mentions use the question as their native preview.

SQLite v15 retains message sticker items and each guild's searchable sticker
catalog. Gateway catalog replacement deletes stale rows for that guild before
writing the new snapshot, while unrelated guild catalogs remain intact.

SQLite v16 retains guild scheduled-event identity, location, associated
channel, start/end time, entity type, lifecycle status, and subscriber count.
Catalog refresh replaces only the selected guild, while Gateway updates use
point writes and deletes so unrelated server events remain available offline.

SQLite v17 retains each message's documented type plus referenced message and
channel IDs. Partial Gateway updates preserve the cached values when Discord
omits them, keeping system-row actions available after live edits and restarts.

SQLite v18 retains forward-reference type and guild identity plus immutable
message snapshots, including content, timestamps, flags, attachments, embeds,
stickers, mentions, and opaque component payloads. The v17 migration preserves
existing references and supplies safe empty snapshot defaults.

SQLite v19 retains each message's complete raw Discord flags. Fresh and partial
Gateway payloads preserve unknown bits, silent-send state, and suppressed-embed
state across live updates, restarts, and future flag additions. The existing
attachment JSON also retains optional voice-message duration and waveform data,
so no destructive table migration is needed for cached audio metadata.

The desktop workspace uses a Discord-like neutral surface hierarchy for the
guild rail, channel list, conversation, and controls. Blurple is reserved for
interactive focus, while presence, warnings, and mentions use independent
semantic colors. The current account and connection state remain anchored at
the bottom of the channel list.

## Native Media

The browser-free video, voice-message, capture, Opus, RTP, DAVE, receive, and
playout architecture is documented in [native media](docs/NATIVE_MEDIA.md).

## Verify

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter test integration_test/discord_social_sdk_bridge_smoke_test.dart -d windows
flutter test integration_test/inline_video_playback_smoke_test.dart -d windows
flutter test integration_test/voice_playback_smoke_test.dart -d windows
flutter build windows --release
```

Run `flutter build macos --release` on macOS and
`flutter build linux --release` on Linux before publishing those packages.
Both runners use the same Dart application and the cross-platform
`media_kit_libs_video` bundle; macOS declares network, microphone, and screen
capture capabilities in its sandbox configuration.

The release executable is written to
`build\windows\x64\runner\Release\flucord.exe`.

## Desktop Protocol Integration

Protocol activation, single-instance forwarding, Linux registration, native
notifications, tray behavior, and signed updates are documented in
[desktop integration](docs/DESKTOP_INTEGRATION.md).

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
