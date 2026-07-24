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
  -> DiscordOAuthIdentityClient
  -> DiscordRestClient (Bearer authorization)
  -> /users/@me + /users/@me/guilds only
```

REST and Gateway classes remain explicitly bot-specific. They are allowed to
extract the bot credential only after `DiscordBotRepositoryFactory` has checked
the session kind. UI, workspace controllers, and repository consumers see only
the session kind and capability set.

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
  identity adapter rejects expired sessions and missing scopes before network
  access. A future authorization-code subsystem must still own login, expiry
  scheduling, refresh-token rotation, revocation, and secure persistence.

## Adapter requirements

A future session adapter must:

1. Declare only capabilities supported by its documented authorization.
2. Reject unsupported full-chat operations before network or cache mutation.
3. Keep refresh and transport secrets outside domain models persisted to
   SQLite, logs, exceptions, and widget state.
4. Translate authentication failures at the repository boundary.
5. Pass the same repository contract and full regression gate before it can
   replace the active workspace transport.
