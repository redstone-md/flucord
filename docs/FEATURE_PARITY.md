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
| Slash commands and components | Ready | Chat-input commands from the channel index, context-menu commands on a message or member, buttons and every select kind, and modals — interaction types 2, 3 and 5 |
| GIF picker | Ready | Trending categories, search with suggestions, sent as a link through Discord's own provider proxy |
| Favourite GIFs, stickers, emoji | Ready | Starred in the account's `FrecencyUserSettings` blob, so they follow the account; each picker leads with what was starred |
| Soundboard | Ready | Server and default sounds sent into a voice channel, and incoming `VOICE_CHANNEL_EFFECT_SEND` fetched from the CDN and played locally — which is how Discord itself does it, since the sound is never mixed into the RTP stream |
| Video and screen share | Built, wired both ways and self-verified | Share, stop, pause and a viewer count from the voice room; watch somebody else's stream in place of the participant grid. 544 real frames became 2151 encrypted packets and came back as 516 pictures at 1280x720; a second Discord account is the only thing left that can confirm delivery over Discord's own servers |
| Camera in a voice channel | Built both ways, unverified over Discord | Media Foundation capture through the same encoder and voice socket as the share; opcode 12 declares the SSRCs and opcode 4 sets `self_video`. Incoming cameras are split off by payload type, attributed by announced SSRC, decoded per sender and drawn in the participant tile |
| User settings | Partial | Both `settings-proto` types read, written and live-updated; groups Flucord cannot apply are shown unavailable |
| Keybinds | Ready | Ten actions bound and carried out from the settings page, stored locally as the desktop client does, and fired system-wide through a low-level keyboard hook that reports without swallowing |
| Screenshots | Ready | Saved as PNG from the same capture path the screen share uses, under a sortable name, with the location reported |
| Clips | Ready | The last thirty seconds of whatever the encoder is producing, muxed to MP4 without re-encoding, saved from a keybind |
| Streamer mode | Partial | Hides invite links and the account name, silences sounds and notifications, keeps the window out of screen recordings, and follows Go Live automatically; hiding overlay widgets is not implemented, since there is no overlay |
| Channel permissions | Ready | Visibility, composer and message actions follow computed permissions |
| Conversation summaries | Ready to receive | `CONVERSATION_SUMMARY_UPDATE` folded into a per-channel store; Discord decides per account whether it sends any |
| Embedded activities, store and Nitro | Not ready | Activities are a separate transport; commerce is outside a chat client's remit |
| ETF Gateway framing | Implemented, not default | Live-checked against a real `HELLO`; a full authenticated `READY` has not been decoded, so the shipped default is JSON |
| zstd-stream Gateway compression | Off by default | Decoder is in place and live-validated, but stays disabled until proven against a full authenticated `READY` |

See [the bundle capability ledger](DISCORD_BUNDLE_COVERAGE.md) for the complete
machine-generated inventory, per-domain status, discovery coverage, and
implementation coverage.

The desktop protocol is private and can change without notice. Matching the
installed client's build profile and headers does not guarantee protocol
stability or account-ban immunity.
