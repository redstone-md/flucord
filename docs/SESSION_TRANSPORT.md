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
  -> DiscordBotRepositoryFactory (current concrete adapter)
  -> DiscordApiClient (Bot-only) + DiscordGatewayClient (Bot-only)

DiscordOAuthUserSession
  <- NativeDiscordOAuthAccountService
     <- system browser authorization + PKCE S256
     <- cross-platform flucord://oauth/discord/callback + state validation
     <- public-client code exchange / refresh rotation
     <- operating-system OAuth grant vault
  -> DiscordOAuthIdentityClient (Bearer authorization)
  -> /users/@me + paginated /users/@me/guilds?with_counts=true only
```

REST and Gateway classes remain explicitly bot-specific. They are allowed to
extract the bot credential only after `DiscordBotRepositoryFactory` has checked
the session kind. UI, workspace controllers, and repository consumers see only
the session kind and capability set.

Production builds disable this bot transport at the application boundary. They
do not read or restore a saved Bot session and do not construct bot credential
controls. `FLUCORD_ENABLE_BOT_TRANSPORT=true` is an explicit developer-build
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

| Capability | Bot application | OAuth2 user session |
| --- | --- | --- |
| Current identity | Yes | `identify` or `email` |
| Guild directory | Yes | `guilds` |
| DM channel directory | Bot-created/live/cache only | `dm_channels.read`, approved partners only |
| Channel messages | Permission-dependent | Not granted by ordinary public OAuth scopes |
| Real-time Gateway | Yes | Not exposed as a full user-client Gateway session |
| Voice connection | Yes | `voice`, approved partners only |

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
