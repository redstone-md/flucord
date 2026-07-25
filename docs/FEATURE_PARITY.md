# Flucord feature parity

This table compares the normal desktop-user path with the installed Discord
desktop client. Bot, OAuth2, and Social SDK features are separate transports and
do not count as desktop-user chat parity.

| Surface | Flucord status | Current boundary |
| --- | --- | --- |
| Native desktop shell | Ready | Flutter widgets; no Electron or WebView |
| Account login | Ready, approval validation pending | Native QR remote-auth handshake and fingerprint live-validated; full mobile approval still pending |
| Saved login | Ready | Versioned operating-system credential vault |
| User profile | Ready | Hydrated from Gateway `READY` |
| Server list | Ready | Hydrated from `READY`/`GUILD_CREATE` |
| Server channels | Ready | Hydrated from `GUILD_CREATE` |
| Direct Message list | Ready | Hydrated from `READY` and live dispatches |
| Channel history | Ready | Desktop REST v9, 100-message cursor pages, SQLite cache |
| Live new/edit/delete events | Ready | Desktop Gateway dispatches |
| Send/edit/delete messages | Ready | Separate desktop-user REST adapter |
| Attachments and replies | Ready | Native multipart upload and existing composer |
| Reactions and pins | Ready | Desktop-user message routes |
| Threads | Partial | Create from message; initial Gateway thread hydration |
| Member list and presence | Partial | Live dispatches only; no Bot member enumeration |
| Search | Local only | Loaded/cached workspace; Discord server search absent |
| Friends | Separate SDK path | Requires approved Discord Social SDK package |
| Voice/video/screen share | Not ready for desktop-user chat | Existing Bot/activity-lobby paths are separate |
| Calls, activities, store, moderation, settings | Not ready | Outside current desktop-user tracer bullet |
| ETF/zstd Gateway framing | Not ready | JSON framing with observed v9 identify/state machine |

The desktop protocol is private and can change without notice. Matching the
installed client's build profile and headers does not guarantee protocol
stability or account-ban immunity.
