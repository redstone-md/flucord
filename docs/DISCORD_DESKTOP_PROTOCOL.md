# Discord desktop protocol snapshot

This inventory records static analysis of the installed Discord desktop client
`1.0.9249` and its renderer assets downloaded on 2026-07-25. It contains no
account tokens, cookies, browser storage, user IDs, message bodies, or captured
request payloads.

The snapshot is an implementation input, not a promise that Discord will keep
the private protocol stable or treat another client as equivalent to its own.

## Analyzed artifacts

- Installed bootstrap `app.asar` and desktop core `core.asar`.
- Renderer `web.b8b5ddfa0f88ae29.js`.
- Renderer `fast-connect.4efb760e37cfd77e.js`.
- Sanitized renderer log lines that describe Gateway connection state only.

## Network profile

| Surface | Installed client value |
| --- | --- |
| REST base | `https://discord.com/api/v9` |
| Gateway base | `wss://gateway.discord.gg` |
| Gateway query | `encoding=etf&v=9&compress=zstd-stream` |
| Client build number | `582977` |
| Normal Gateway capabilities | `1734653` |
| Obfuscated-channel capabilities | `1767421` |
| Guild subscription batch limit | `15360` encoded bytes |

The Gateway may return a regional resume URL in `READY`; subsequent reconnects
use it until the session is cleared.

## REST request preparation

For API-relative URLs, the renderer request hook adds the raw account
`Authorization` value and dynamically supplies these headers when available:

```text
X-Super-Properties
X-Fingerprint
X-Installation-ID
Accept-Language
X-Discord-Locale
X-Discord-Timezone
X-Debug-Options
X-Routing-Key
x-client-trace-id
```

The base64 JSON in `X-Super-Properties` includes:

```text
os
browser
device
system_locale
browser_user_agent
browser_version
os_version
release_channel
client_build_number
native_build_number
client_event_source
has_client_mods
client_launch_id
launch_signature
client_heartbeat_session_id
client_app_state
```

These fields are runtime state, not a static header string. The official
renderer updates heartbeat and application state before preparing requests.

## Core chat REST operations

| Operation | Method and route | Observed payload/query |
| --- | --- | --- |
| Channel history | `GET /channels/{channel}/messages` | `before`, `after`, `around`, `limit`, optional `preload`, `feature` |
| Send message | `POST /channels/{channel}/messages` | `content`, `nonce`, `tts`, `flags`, optional references, mentions, attachments, stickers, poll |
| Edit message | `PATCH /channels/{channel}/messages/{message}` | edited fields such as `content`, `components`, `allowed_mentions` |
| Delete message | `DELETE /channels/{channel}/messages/{message}` | no body |
| ACK message | `POST /channels/{channel}/messages/{message}/ack` | `token`, `last_viewed`, `flags` |
| Bulk ACK | `POST /read-states/ack-bulk` | `read_states[]` with channel, message, and read-state type |
| Open DM/GDM | `POST /users/@me/channels` | `recipients[]` |

## Native QR remote auth

Flucord creates a fresh RSA-2048 key pair for every login attempt and connects
to remote-auth Gateway v2. The public key is sent as base64 SubjectPublicKeyInfo.
The client decrypts Discord challenges with RSA-OAEP/SHA-256, returns an
unpadded base64url SHA-256 nonce proof, renders only the returned fingerprint as
`https://discord.com/ra/{fingerprint}`, and exchanges `pending_login.ticket`
through `POST /users/@me/remote-auth/login`. Before that exchange, the client
loads `/experiments` and retains Discord's fingerprint in the desktop request
context. When Discord returns `captcha-required`, Flucord renders the supplied
site key and `captcha_rqdata` in a short-lived system WebView2, then retries the
same ticket with `X-Captcha-Key`, `X-Captcha-Rqtoken`, and the optional
`X-Captcha-Session-Id` headers used by the installed renderer. The returned
encrypted account session is decrypted in memory and immediately handed to the
typed session vault boundary. RSA private material, tickets, CAPTCHA tokens,
and decrypted credentials never enter SQLite, logs, or the QR payload.

The WebView loads only `discord.com/login`, replaces the document with the
hCaptcha surface, denies permission and popup requests, and clears its cookies
and cache before disposal. Discord's application UI, REST, Gateway, and chat
surfaces remain native Flutter and Dart code.

On Windows, both remote auth and the main desktop Gateway use the operating
system's WinHTTP WebSocket stack through Dart FFI. Discord's Cloudflare edge
rejects the otherwise equivalent `dart:io` TLS handshake before protocol
negotiation. WinHTTP runs in a worker isolate so blocking receive calls never
occupy Flutter's UI isolate; Dart still owns framing, cryptography, heartbeat,
resume, and login state.

Observed remote-auth operations:

```text
hello -> init -> nonce_proof -> pending_remote_init
      -> pending_ticket -> pending_login -> captcha-required
      -> captcha solution + same ticket -> encrypted_token
```

The outgoing message queue strips local-only fields before POST, tracks a
nonce, retries rate limits, and reconciles the optimistic message against both
the REST response and the Gateway `MESSAGE_CREATE` dispatch.

## Gateway framing

The renderer requests `encoding=etf` and packs every outgoing frame with the
native `discord_erlpack` module, falling back to a WebAssembly `wetf` parser
when the native module is absent. Its parser is configured with
`binary:"utf8"`, `string:"array"`, `nil:"array"`, and the atom table
`{nil: null, null: null, true: true, false: false}`.

Flucord implements that exact External Term Format subset in Dart. The decoder
covers `SMALL_INTEGER`, `INTEGER`, `NEW_FLOAT`, the legacy 31-byte `FLOAT`,
all four atom tags, `SMALL_TUPLE`, `LARGE_TUPLE`, `NIL`, `STRING`, `LIST`,
`BINARY`, `BIT_BINARY`, `SMALL_BIG`, `LARGE_BIG`, and `MAP`. It rejects
improper list tails, payload compression, unsupported tags, truncated buffers,
trailing bytes, and nesting past 128 levels. The encoder writes atoms for
`null`/`true`/`false`, the narrowest integer representation, `NEW_FLOAT`
doubles, UTF-8 binaries for strings, `NIL`-terminated proper lists, and maps.

Frames travel as binary WebSocket messages. The WinHTTP transport accepts
`BINARY_MESSAGE`/`BINARY_FRAGMENT` buffer types and sends with
`BINARY_MESSAGE`; the `dart:io` transport writes `Uint8List` payloads. The
opcode 37 batching budget is measured in encoded ETF bytes rather than JSON
bytes, because Discord counts the encoded size.

Flucord now requests `compress=zstd-stream` as well, decoding it with its own
pure-Dart RFC 8878 decompressor. Discord's `discord_zstd` native module cannot
be redistributed, so the decoder was written from the format specification and
checked against libzstd 1.5.7: a committed corpus of reference frames plus
hand-built frames covering block types libzstd never emits for these inputs.

Transport compression and payload encoding sit behind one transport codec, so
they are always reset together. A decompressor that survived a reconnect would
resolve matches against the previous session's bytes. Outgoing frames are never
compressed; the Gateway does not ask a client to compress. The JSON encoding and
the uncompressed transport both remain selectable through the profile and stay
covered by tests.

## Gateway identify and resume

Normal opcode `2` data:

```text
token
capabilities
properties
presence
compress
client_state
```

Fast-connect opcode `2` is sent before the main renderer takes ownership. It
sets `properties.is_fast_connect=true`, includes `installation_id` when known,
and starts with `client_state.guild_versions={}`. The main renderer does not
send a duplicate identify after adopting that socket.

Normal identify restores committed cache versions when available:

```text
guild_versions
highest_last_message_id
read_state_version
user_guild_settings_version
user_settings_version
private_channels_version
api_code_version
initial_guild_id
```

Opcode `6` resume data is `token`, `session_id`, and `seq`.

## Gateway state machine

1. Connect with ETF and zstd-stream, then wait for opcode `10` `HELLO`.
2. Start heartbeat scheduling with random initial jitter.
3. Send opcode `40` QoS heartbeat with `seq` and `qos`.
4. Treat a missing opcode `11` ACK before the next interval as a reconnect.
5. On opcode `7`, reconnect immediately.
6. On opcode `9`, resume only when the server permits it and session state is
   still present; otherwise clear session state and identify again.
7. `READY` stores `session_id` and `resume_gateway_url`.
8. `READY_SUPPLEMENTAL` completes initial hydration; `RESUMED` completes replay.

The official client accepts server opcode `1` as an immediate heartbeat
request and resets its periodic interval after responding.

## Private channel directory

`READY` carries DM and group-DM channels in `private_channels` and never
repeats a user object: a channel may arrive with `recipient_ids` in place of
`recipients`. Every id resolves against the flat top-level `users` array, and
the compressed field is dropped once expanded. That table also backs the
`user_id` references in `merged_members` and `merged_presences`, so it lives
from `READY` until `READY_SUPPLEMENTAL` has been applied and is dropped
immediately afterwards.

`READY_SUPPLEMENTAL.lazy_private_channels` is a late top-up with the same
shape. It is not merged incrementally: the directory is rebuilt from the
remembered `READY` list and the lazy entries are applied over that.

The DM list is ordered by an effective last-message snowflake, never by
recipients. The key is the read-state cursor, else the channel's
`last_message_id`, else the channel id itself, raised to the message-request
timestamp when that is the newer of the two; the list runs descending by that
snowflake's timestamp.

## Guild subscriptions

The current renderer no longer sends each update through opcode `14`. It
aggregates per-guild state and sends opcode `37` with:

```json
{
  "subscriptions": {
    "guild_id": {
      "typing": true,
      "threads": true,
      "activities": true,
      "member_updates": false,
      "members": [],
      "channels": {},
      "thread_member_lists": []
    }
  }
}
```

Batches split before the encoded sum of `[guild_id, subscription]` entries
exceeds 15,360 bytes.

## Flucord boundary

The Dart implementation now owns QR remote auth, a versioned vault-backed
desktop-user session, raw desktop REST authorization, rate-limit execution, a
Gateway v9 client, opcode 37 subscriptions, and Gateway-first workspace
hydration from `READY`, `READY_SUPPLEMENTAL`, and `GUILD_CREATE`. Channel
history and message mutations use the observed client routes. The desktop path
does not call `/gateway/bot`, send Bot intents, enumerate guild members through
the Bot REST facade, read Discord storage, or adopt Discord's running socket.

The full Windows tracer bullet was interactively validated on 2026-07-25:
phone QR approval, mandatory hCaptcha, encrypted session exchange, main Gateway
bootstrap, authenticated identity, guild/channel projection, channel history,
and vault-backed restart restoration all completed without copying Discord
storage or logging the session credential.

The socket now matches the installed client's transport exactly:
`encoding=etf`, `v=9`, and `compress=zstd-stream`.

A machine-generated inventory of the installed client, its native modules, and
the complete renderer chunk corpus lives in
[`DISCORD_BUNDLE_COVERAGE.md`](DISCORD_BUNDLE_COVERAGE.md) and is regenerated by
`tool/inventory_discord_bundles.ps1`.

The installed-client snapshot is private and versioned. Header similarity does
not establish protocol stability or account-ban immunity.
