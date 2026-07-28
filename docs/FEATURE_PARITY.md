# Flucord feature parity

This table compares the normal desktop-user path with the installed Discord
desktop client. Bot, OAuth2, and Social SDK features are separate transports and
do not count as desktop-user chat parity.

| Surface | Flucord status | Current boundary |
| --- | --- | --- |
| Native desktop shell | Ready | Flutter widgets; no Electron or embedded Discord UI |
| Account login | Ready | Native QR remote-auth plus an ephemeral system WebView2 for mandatory hCaptcha; phone approval and challenge completion live-validated |
| Saved login | Ready | Versioned operating-system credential vault |
| User profile | Ready | Hydrated from Gateway `READY`; display name, pronouns, about me, accent colour, avatar and banner edited over `PATCH /users/@me`, each field three-state so an untouched image is never cleared |
| Server list | Ready | Hydrated from `READY`/`GUILD_CREATE` |
| Server channels | Ready | Hydrated from `GUILD_CREATE` |
| Direct Message list | Ready | `READY.users` expansion gives recipients names and avatars; ordered by last activity |
| Channel history | Ready | Desktop REST v9, 100-message cursor pages, SQLite cache |
| Live new/edit/delete events | Ready | Desktop Gateway dispatches |
| Send/edit/delete messages | Ready | Separate desktop-user REST adapter |
| Attachments and replies | Ready | Native multipart upload and existing composer |
| Inline video playback | Ready | Native playback, seek, mute, explicit fullscreen exit, and deterministic teardown |
| Reactions and pins | Ready | Desktop-user message routes |
| Threads | Ready | Create from message, archived-thread paging, join and leave with a live member count, and the lazy roster from `THREAD_MEMBER_LIST_UPDATE` |
| Voice channel text chat | Ready | Room and timeline switch inside a voice channel |
| Member list and presence | Ready | Server-authoritative lazy member list with scroll-driven subscriptions; presence, activities, hidden activities and the account's own custom status all read and published |
| Search | Ready | Server-side `GET /guilds/{id}/messages/search` and the DM equivalent, with the loaded page filtered locally as you type |
| Friends | Separate SDK path | Requires approved Discord Social SDK package |
| Server voice channels | Ready | Desktop-user session joins over its own gateway; occupants read from `READY_SUPPLEMENTAL.guilds[].voice_states` and shown per channel; joins without DAVE on the transport cipher; live audio interoperability still unverified |
| DM and group calls | Ready | Opcode 13, ring and decline, incoming-call surface; live interoperability unverified |
| Stage channels | Ready | Type 13 recognised, live instance and topic; audience may request to speak, withdraw, accept an invitation and step down; a moderator may start, rename and end a stage and move anybody on or off it |
| GIF picker | Ready | Trending categories, search with suggestions, sent as a link through Discord's own provider proxy |
| Soundboard | Ready to send | Server and default sounds, played into a voice channel; incoming `VOICE_CHANNEL_EFFECT_SEND` is surfaced but the sound itself is not played back locally |
| Video and screen share | Not ready | Opcodes 18-22; needs a native capture and encoder library |
| User settings | Partial | `settings-proto` read, write and live update; groups Flucord cannot apply are shown unavailable |
| Channel permissions | Ready | Visibility, composer and message actions follow computed permissions |
| Calls, activities, store, moderation, settings | Not ready | Outside current desktop-user tracer bullet |
| ETF Gateway framing | Implemented, not default | Live-checked against a real `HELLO`; a full authenticated `READY` has not been decoded, so the shipped default is JSON |
| zstd-stream Gateway compression | Off by default | Decoder is in place and live-validated, but stays disabled until proven against a full authenticated `READY` |

See [the bundle capability ledger](DISCORD_BUNDLE_COVERAGE.md) for the complete
machine-generated inventory, per-domain status, discovery coverage, and
implementation coverage.

The desktop protocol is private and can change without notice. Matching the
installed client's build profile and headers does not guarantee protocol
stability or account-ban immunity.
