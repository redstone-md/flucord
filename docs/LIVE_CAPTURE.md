# Live gateway capture

This records what one real session on a small test account showed. It replaces
some of the audit's assumptions with facts, and it says clearly which questions
are still open. It holds no names, ids, tokens or message text.

## How it was captured

- One test account, about 42 minutes of connected time on one day.
- Five connections with pauses between them: the first identify (30 minutes), one
  resume (5 minutes), and three fresh identifies (2 to 3 minutes each).
- The socket used the same identify shape as the desktop transport, with JSON
  frames and no transport compression, which are the client's current defaults.
- The session was passive. After login it sent only heartbeats. It did **not**
  send opcode 37 guild subscriptions, and it sent no messages.

Account size, as rough buckets:

| Thing | Size |
| --- | --- |
| Guilds | under 10 |
| Guild sizes | from under 10 members to over 100,000 |
| Direct and group DM channels | about 10 |
| Read state entries | under 100 |
| Channels, all guilds | a few hundred, most of them in one guild |
| Roles, all guilds | a few hundred |

## Event rates

Rates over all five connections, leaving out the login frames.

| Event | Per minute |
| --- | --- |
| `PASSIVE_UPDATE_V2` | about 0.6 |
| `PRESENCE_UPDATE` | about 0.3 |
| `CHANNEL_UPDATE` | about 0.1 |
| `MESSAGE_CREATE`, `TYPING_START`, `MESSAGE_ACK` | none seen |

The busiest 10 seconds after login held 2 events.

Login frames, once per identify:

| Frame | Size | Arrival after the socket opens |
| --- | --- | --- |
| `READY` | about 700 KB | under 1 second |
| `READY_SUPPLEMENTAL` | about 20 KB | under 1 second |
| `SESSIONS_REPLACE` | under 1 KB | soon after |

The resume answered with `RESUMED` in under 1 second and replayed no events.

### What these numbers can tell us

- A quiet account with no subscriptions gets very little traffic. Guild activity
  reaches it as `PASSIVE_UPDATE_V2` (channel pointers, voice states and members),
  not as messages.
- `READY` is the heavy frame, and its size is known for an account of this size.

### What they cannot tell us

- **They are not a rate for a big account.** A test account may be far quieter
  than a big one. Do not use these numbers to size a buffer or a budget.
- They are not the rate the app sees. Right after `READY` the app sends opcode 37
  for every guild, and for open channels, which should add messages, typing and
  member list traffic. This capture did not send it, so that traffic is not
  measured here.
- 42 minutes on one day says nothing about peak hours.

## The five server questions

| Question | Answer |
| --- | --- |
| Does a new mention send a read state update? | **Open.** No mention arrived. Needs a second account to send one. |
| Does the sender get `MESSAGE_ACK`? | **Open.** The account owns no guild, so there was nowhere safe to post a test message, and none was sent. Needs a guild where the account is the only human member. |
| What is `retry_after` in slowmode? | **Open.** Needs a slowmode channel and a send. |
| How often do lazy DMs and unavailable guilds occur on reconnect? | **Not seen on this account.** Across 4 identifies, every guild was available and `lazy_private_channels` was empty each time. This is a small sample on a small account, so it does not show they are rare on a big one. |
| Does Discord stay silent on `STREAM_WATCH` while this client is still listed? | **Open.** Needs a streamer and a join, which this capture did not do. |

The check on Windows of the Send button and layout findings is also still open.
It needs a Windows machine.

## Other facts from READY

- A guild's name and most of its fields sit under `properties`.
- Direct and group DM channels carry `recipient_ids`, and each id resolves in the
  top-level `users` list. That list also holds the account itself.
- Every guild entry carries `emojis` and `stickers` lists.
- On this account, the first part of the token, base64-decoded, is the account id.

## The READY fixture

`test/fixtures/gateway/ready_sanitized.json` holds a sanitized READY, used by
`test/ready_fixture_test.dart`.

An allowlist built it, so anything not known to be safe is dropped or replaced:

- Keys not on a reviewed list of protocol names are dropped.
- Every id becomes a synthetic one. Sorting synthetic ids gives the same order as
  the real ones, and a repeated id stays the same, so references still line up.
- Every other string becomes a fixed placeholder, including names, topics, hashes,
  timestamps, locales and urls.
- Numbers become 0 and booleans become false, except a few structural fields such
  as a channel's `type`.
- Permission bits are a fixed value, so channels stay visible to the mapper.

The lists are shrunk. The fixture has 3 guilds, a few channels of each type per
guild, and only the users it refers to. The real sizes are the buckets above. So
do not read counts or field values from the fixture as facts about any account.
Only its structure is real.

The stored output was searched before this was committed: the whole branch diff
and the commit messages, for the token, its parts, the account's id, username and
email, and every real id seen in the capture. The raw capture was deleted
afterwards.
