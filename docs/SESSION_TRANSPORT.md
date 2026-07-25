# Discord session transport

## Purpose

Flucord's native workspace must not depend on how a Discord identity was
authorized. The application layer therefore receives a typed
`DiscordAccountSession`; it never forwards an ambiguous token string to a
generic repository factory.

## Boundary

```text
ConnectionController
  -> DiscordAccountSession + capabilities
  -> ChatRepositoryFactory (domain contract)
  -> DiscordRepositoryFactory
     -> DiscordDesktopChatRepository
        -> DiscordDesktopApiClient + DiscordDesktopGatewayClient
     -> DiscordBotRepositoryFactory (developer build only)
        -> DiscordApiClient + DiscordGatewayClient

DiscordDesktopUserSession
  <- native QR remote-auth Gateway v2 + RSA-OAEP/SHA-256
     (Windows system WinHTTP WebSocket; no browser runtime)
  <- operating-system session vault
  -> Gateway v9 READY/GUILD_CREATE workspace hydration
     (Windows system WinHTTP WebSocket; no browser runtime)
  -> raw desktop REST authorization for history and message operations

DiscordOAuthUserSession
  <- NativeDiscordOAuthAccountService
     <- system browser authorization + PKCE S256
     <- cross-platform flucord://oauth/discord/callback + state validation
     <- public-client code exchange / refresh rotation
     <- operating-system OAuth grant vault
  -> DiscordOAuthIdentityClient (Bearer authorization)
  -> /users/@me + paginated /users/@me/guilds?with_counts=true only
```

Bot REST and Gateway classes remain explicitly bot-specific. They are allowed to
extract the bot credential only after `DiscordBotRepositoryFactory` has checked
the session kind. The desktop-user adapter is independent and never calls
`/gateway/bot`, sends Bot intents, or injects its credential into the Bot
facade. UI, workspace controllers, and repository consumers see only the
session kind and capability set.

Production builds restore desktop-user sessions while leaving saved Bot
sessions dormant and omitting bot credential controls.
`FLUCORD_ENABLE_BOT_TRANSPORT=true` is an explicit developer-build
opt-in; even then, the transport remains visually and structurally separate
from the normal OAuth and Social SDK account path.

## Account setup

For a normal account, enable **Public Client** for the Discord application and
register `flucord://oauth/discord/callback`. Run with the public application ID:

```powershell
flutter run -d windows `
  --dart-define=FLUCORD_DISCORD_CLIENT_ID=123456789012345678
```

Connections → **Connect Discord** requests `identify`, `guilds`,
`guilds.members.read`, and `connections`. The separately distributed Social
SDK package uses the same public application ID and its own grant vault for
approved relationship and Direct Message access.

`DiscordAccountConnectionController` presents these independent lifecycles as
one onboarding action. It completes ordinary OAuth first, invokes native Social
SDK authorization only when that package is available, and disconnects both
grants without copying access or refresh tokens between controllers or vaults.
After every native authorization or refresh restore, the bridge reads the
crash-safe `Client::GetCurrentUserV2()` identity and compares its snowflake with
the ordinary OAuth `/users/@me` account. Friends, Direct Messages, and presence
remain unavailable until the IDs match. A mismatch clears only the Social SDK
grant, retains the linked OAuth profile, and retries only native social
authorization so data from another Discord account cannot cross the boundary.

For the optional developer transport, create a Discord application bot, enable
the Message Content, Server Members, and Presence intents, and install it with
the permissions required by the test server. Then opt in explicitly:

```powershell
flutter run -d windows `
  --dart-define=FLUCORD_ENABLE_BOT_TRANSPORT=true
```

Expand **Developer bot transport** in Connections. Remembered credentials stay
in the operating-system vault; legacy `discord_bot_token` records migrate only
when this developer path is enabled and used.

`DiscordRestClient` owns the shared HTTP, JSON, retry, and rate-limit behavior.
Its sealed authorization value writes either the documented `Bot` or `Bearer`
scheme and redacts the credential from string output. The Bot chat facade can
only construct Bot authorization; a Bearer value cannot be injected into its
message, channel, or `/gateway/bot` methods.

## Capability matrix

| Capability | Desktop user | Bot application | OAuth2 user session |
| --- | --- | --- | --- |
| Current identity | Gateway READY | Yes | `identify` or `email` |
| Guild directory | Gateway READY/GUILD_CREATE | Yes | `guilds` |
| DM channel directory | Gateway READY/live | Bot-created/live/cache | `dm_channels.read`, approved partners only |
| Channel messages | Permission-dependent | Permission-dependent | Not granted by public OAuth scopes |
| Real-time Gateway | Desktop v9 | Bot Gateway | Not a full user Gateway session |
| Voice connection | Pending desktop transport validation | Yes | `voice`, approved partners only |

The matrix describes protocol-level availability, not server permissions. A
bot can still receive `403` for an operation its guild role does not permit.

`messages.read` is a local Discord RPC scope; it is not treated as REST access
to a user's channel history. Flucord also does not infer chat access from
`dm_channels.read`.

## Credential ownership

- Session `toString()` implementations redact secrets.
- The active credential exists only in the typed session and the concrete
  transport that consumes it.
- Remembered Bot sessions are encoded as one versioned JSON record in the
  operating-system credential vault.
- Remembered desktop-user sessions use the same versioned session codec and
  operating-system vault. Remote-auth private keys and tickets are memory-only.
- The legacy `discord_bot_token` key remains readable and is deleted after the
  next successful versioned write.
- OAuth access tokens are not persisted by the Bot credential codec. The OAuth
  account service uses a separate versioned grant record containing the access
  token, rotated refresh token, granted scopes, and expiry. It refreshes before
  identity access and writes the replacement grant through the operating-system
  credential vault.
- The native public-client flow generates a fresh PKCE verifier and random
  `state` for every attempt. The token exchange sends `client_id`, never embeds
  a client secret, and accepts the callback only on the exact registered
  `flucord://oauth/discord/callback` route.
- Widgets and application controllers see only immutable `DiscordOAuthAccount`
  profile, `DiscordOAuthConnection`, and `DiscordOAuthGuild` directory metadata.
  Access tokens, refresh tokens, authorization codes, and the PKCE verifier
  remain inside data-layer services and the credential vault.
- `OAuthGuildDirectoryController` owns only the account-home versus authorized
  guild navigation destination. It projects immutable OAuth directories into
  the disconnected native shell and never manufactures friends, channels,
  messages, read state, or Gateway presence.
- `OAuthGuildMembershipController` owns asynchronous, per-guild server state
  for the documented `guilds.members.read` endpoint. It caches current-user
  membership independently from selection, rejects stale responses after an
  account change, and retains no access or refresh tokens.
- The `identify` account snapshot includes only documented current-user profile
  metadata: banner/accent, discriminator, locale, verification, MFA, and public
  flags. Email remains absent because Flucord does not request `email`.
- `relationships.read` belongs to the separately distributed native Discord
  Social SDK and requires its terms plus application approval. It is not a
  public REST relationship endpoint and is never emulated with private routes.
- Relationship snapshots use the SDK-owned `UserHandle` identity, including
  its generated GIF/WebP CDN avatar URL, display name, unique username,
  presence, provisional-account flag, snowflake, and the optional Rich Presence
  returned by `UserHandle::GameActivity()`. That activity is limited by the SDK
  to the current Discord application; it is not a directory of every activity
  shown by the official client. The native Friends surface presents that data
  in an anchored profile without querying a private user endpoint and routes
  its Message action through the existing Social SDK DM controller.
- Activity invites use only the documented Social SDK flow:
  `CreateOrJoinLobby` publishes an ephemeral join secret through
  `UpdateRichPresence`, `SendActivityInvite` targets a friend, native
  create/update callbacks retain the exact invite object, and
  `AcceptActivityInvite` returns the secret used for the recipient's lobby
  join. Activity-lobby state is isolated from normal DM state and is never
  labelled as a direct call. After either side owns the lobby ID, the native
  bridge uses documented `StartCall(lobbyId)` audio, retains the returned
  `discordpp::Call`, forwards its status, participant, and speaking callbacks,
  applies self-mute and self-deafen through that exact call, and leaves through
  `EndCalls`. Remote participant volume is local-only: the bridge validates a
  live non-self participant, applies documented `Call::SetLocalMute`, and
  projects `Call::GetLocalMute` plus the authenticated current-user snowflake
  back into immutable Flutter state. The bridge owns an in-memory speaking-user
  set, removes users when speaking stops or they leave, and projects only typed
  snowflakes into Flutter. Flutter never handles PCM or Discord voice
  credentials itself.
  Lobby secrets are generated with operating-system cryptographic randomness,
  cross only the private platform channel, remain outside controllers and
  persistence, and are wiped from the native bridge when the SDK session ends.
  Call handles and participant state are also memory-only and are discarded on
  Social SDK disconnect or authentication expiry. This remains an activity
  lobby call rather than an ordinary user-DM call, because the documented SDK
  still does not expose a DM channel/lobby ID for direct calling.
  Known participant snowflakes resolve through the existing live relationship
  directory; unknown participants retain a non-fabricated identity fallback.
  The current account is labelled **You** and has no remote-mute action. Other
  rows retain independent pending/error state, and speaking remains visible
  while their audio is locally muted.
  Audio-device selection remains pending until the approved SDK package can
  supply exact input/output enumeration signatures for package-linked testing.
- Social SDK grants have their own versioned operating-system vault record.
  The Windows bridge owns one persistent `discordpp::Client`, performs the SDK
  PKCE/refresh flow, waits for `Client::Status::Ready`, and pumps callbacks on
  the runner UI thread before exposing relationships or mutations. Its grants
  never enter the Bot credential codec or the ordinary OAuth grant vault.

## Desktop protocol delivery

`DesktopProtocolRouter` is the single parser for channel navigation and OAuth
callbacks. Windows and macOS feed it from `protocol_handler`; macOS also
declares `flucord` in `CFBundleURLTypes`. Linux does not pretend the plugin has
support it lacks: the GTK runner is a unique `GApplication`, forwards secondary
`flucord://` invocations over a native Flutter method channel, and receives a
cold-start URL through Dart entrypoint arguments. A native queue and explicit
Dart readiness handshake prevent callbacks from being lost while the Flutter
isolate starts. The packaged `.desktop` file declares
`x-scheme-handler/flucord` for the system MIME application registry.

## Adapter requirements

A future session adapter must:

1. Declare only capabilities supported by its documented authorization.
2. Reject unsupported full-chat operations before network or cache mutation.
3. Keep refresh and transport secrets outside domain models persisted to
   SQLite, logs, exceptions, and widget state.
4. Translate authentication failures at the repository boundary.
5. Pass the same repository contract and full regression gate before it can
   replace the active workspace transport.
