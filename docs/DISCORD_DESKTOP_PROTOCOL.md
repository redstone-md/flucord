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

The outgoing message queue strips local-only fields before POST, tracks a
nonce, retries rate limits, and reconciles the optimistic message against both
the REST response and the Gateway `MESSAGE_CREATE` dispatch.

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

The Dart implementation currently provides deterministic protocol builders and
state-machine tests only. It does not read Discord storage, adopt Discord's
running socket, or provide an account credential source. ETF/zstd framing, a
vault-owned account session, rate-limit execution, cache hydration, and live
interoperability remain separate increments.
