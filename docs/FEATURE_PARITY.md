# Flucord feature parity

This table compares the normal desktop-user path with the installed Discord
desktop client. Bot, OAuth2, and Social SDK features are separate transports and
do not count as desktop-user chat parity.

| Surface | Flucord status | Current boundary |
| --- | --- | --- |
| Native desktop shell | Ready | Flutter widgets; no Electron or embedded Discord UI |
| Account login | Ready | Native QR remote-auth plus an ephemeral system WebView2 for mandatory hCaptcha; phone approval and challenge completion live-validated |
| Saved login | Ready | Versioned operating-system credential vault |
| User profile | Ready | Hydrated from Gateway `READY` |
| Server list | Ready | Hydrated from `READY`/`GUILD_CREATE` |
| Server channels | Ready | Hydrated from `GUILD_CREATE` |
| Direct Message list | Ready | `READY.users` expansion gives recipients names and avatars; ordered by last activity |
| Channel history | Ready | Desktop REST v9, 100-message cursor pages, SQLite cache |
| Live new/edit/delete events | Ready | Desktop Gateway dispatches |
| Send/edit/delete messages | Ready | Separate desktop-user REST adapter |
| Attachments and replies | Ready | Native multipart upload and existing composer |
| Inline video playback | Ready | Native playback, seek, mute, explicit fullscreen exit, and deterministic teardown |
| Reactions and pins | Ready | Desktop-user message routes |
| Threads | Partial | Create from message; initial Gateway thread hydration |
| Voice channel text chat | Ready | Room and timeline switch inside a voice channel |
| Member list and presence | Ready for guild rosters | Server-authoritative lazy member list with scroll-driven subscriptions; presence beyond what a roster item carries is still open |
| Search | Local only | Loaded/cached workspace; Discord server search absent |
| Friends | Separate SDK path | Requires approved Discord Social SDK package |
| Server voice channels | Ready | Desktop-user session joins over its own gateway; live interoperability still unverified |
| DM and group calls | Ready | Opcode 13, ring and decline, incoming-call surface; live interoperability unverified |
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
