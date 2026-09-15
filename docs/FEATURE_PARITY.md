# Flucord feature parity

This table compares the normal desktop-user path with the installed Discord
desktop client. Bot, OAuth2, and Social SDK features are separate transports and
do not count as desktop-user chat parity.

| Surface | Flucord status | Current boundary |
| --- | --- | --- |
| Native desktop shell | Ready | Flutter widgets; no Electron or embedded Discord UI |
| Account login | Ready | Native QR remote-auth plus an ephemeral system WebView2 for mandatory hCaptcha; phone approval and challenge completion live-validated |
| Saved login | Ready | Versioned operating-system credential vault |
| Account security | Ready | TOTP, SMS and backup codes as before, plus security-key enrolment and verification through the Windows platform authenticator, next to the other second factors; authorised applications are listed and revoked; a data package can be requested from settings with its status shown |
| User profile | Ready | Hydrated from Gateway `READY`; display name, pronouns, about me, accent colour, avatar and banner edited over `PATCH /users/@me`, each field three-state so an untouched image is never cleared |
| Other-user profiles | Ready | The member popover fetches the other user's profile: bio, banner, badges, avatar decoration, connections, mutual servers and mutual friends, each falling back gracefully when absent; a private note on the person rides the account's own note blob and survives a restart |
| Connections | Ready | Third-party accounts listed, linked and unlinked through the desktop-user adapter; a link starts on the service's own page; a service Discord refuses is named rather than read as an outage |
| Entitlements | Partial | A read-only page shows the Nitro tier, the boosts held, and what they change; nothing here can alter a grant |
| App authorisation | Ready | A bot or app invite is read in-app, the requested scopes are named, and consent adds the app to a chosen server; refusals are said plainly |
| Data package | Ready | A request starts from settings and its status is shown; the package itself arrives by email, between the person and Discord |
| Server list | Ready | Hydrated from `READY`/`GUILD_CREATE` |
| Joining, creating, leaving servers | Ready | Invites resolve to a preview in-app, joining hydrates the rail, channels, roles, members and read state without a restart, and leave asks first; live validation of the join round-trip on a real invite is still unverified |
| Server channels | Ready | Hydrated from `GUILD_CREATE` |
| Channel configuration | Ready | The channel editor exposes topic, slowmode, age gate, bitrate, user limit, parent and voice region; per-role and per-member permission overwrites are editable and private channels follow the computed permissions; webhooks are listed, created, edited and deleted from guild settings, gated on the manage-webhook permission; the composer counts down a channel's slowmode |
| Channel permissions | Ready | Visibility, composer and message actions follow computed permissions |
| Direct Message list | Ready | `READY.users` expansion gives recipients names and avatars; ordered by last activity |
| Message requests | Ready | Direct messages from strangers land in their own folder with accept and decline; accepting moves the conversation into the DM list, declining removes it, and both ack the request's read state |
| Notification centre | Ready | Mentions across servers gather per channel with jump targets; opening the centre acks it, and each channel can be marked read from its row |
| Channel history | Ready | Desktop REST v9, 100-message cursor pages, SQLite cache |
| Live new/edit/delete events | Ready | Desktop Gateway dispatches |
| Send/edit/delete messages | Ready | Separate desktop-user REST adapter |
| Text to speech | Ready | Incoming spoken-aloud messages render with their flag and are read through the media playback layer where the account's setting allows; `/tts` sends one the same way; non-Windows platforms say the speech voice is unavailable rather than playing nothing |
| Silent messages | Ready | An incoming silent message carries its marker |
| Composer checks | Ready | A character counter appears near the limit, attachment sizes are checked against the tier- and entitlement-derived limit before upload, and a file can be tagged as a spoiler at attach time, arriving spoiler-tagged |
| Attachments and replies | Ready | Native multipart upload and existing composer |
| Inline video playback | Ready | Native playback, seek, mute, explicit fullscreen exit, and deterministic teardown |
| Reactions and pins | Ready | Desktop-user message routes |
| Threads | Ready | Create from message, archived-thread paging, join and leave with a live member count, and the lazy roster from `THREAD_MEMBER_LIST_UPDATE` |
| Voice channel text chat | Ready | Room and timeline switch inside a voice channel |
| Member list, roles and presence | Ready | Server-authoritative lazy member list with scroll-driven subscriptions; presence, activities, hidden activities and the account's own custom status all read and published. The role editor offers every permission bit, colour and icon; the member popover grants roles and applies nickname, timeout, kick and ban, gated on computed permissions; the list is searched in large servers through the member-chunk mechanism |
| Search | Ready | Server-side `GET /guilds/{id}/messages/search` and the DM equivalent, with the loaded page filtered locally as you type; from, mentions, has, in, before, after and pinned are offered as controls that fill the same grammar tokens |
| Message and channel links | Ready | A `discord.com` conversation link the account can reach opens in-app and lands on the message through the around-anchor history read; anything else goes to the external launcher |
| Friends | Separate SDK path | Requires approved Discord Social SDK package |
| Server voice channels | Ready | Desktop-user session joins over its own gateway; occupants read from `READY_SUPPLEMENTAL.guilds[].voice_states` and shown per channel; joins without DAVE on the transport cipher; live audio interoperability still unverified; the microphone goes out only above a threshold that sits 10 dB over the room's noise floor (the quietest of the last three seconds), with a 400 ms hangover, and "speaking" is read off arriving audio rather than the speaking opcode |
| Room listening controls | Ready | Each participant tile carries a volume slider that survives a restart; other applications are attenuated while this account speaks, through WASAPI session volumes, with an on-or-off switch and a level; ring, accept and hang-up are bundled sounds on the playback layer, the ring repeating until answered |
| Capture controls | Ready | A manual sensitivity control overrides the automatic noise-floor gate, push-to-talk keeps transmitting for its release delay, and echo cancellation and automatic gain control are applied in the native capture module; all four settings persist |
| Noise suppression | Built, measured locally | DeepFilterNet (MIT) on the microphone path between the framer and the Opus encoder, off by default, switched from voice settings; 2 ms per 20 ms frame, 29 ms model delay, noise floor between words 30 dB lower on synthesised speech; not yet judged by a remote listener over Discord |
| Game detection and Rich Presence | Ready | Running games are detected by process scanning on Windows against `GET /applications/detectable` and published as the playing activity, honouring the show-current-game setting; the documented local Rich Presence interface is served over the unix socket on Linux and macOS and the named pipe on Windows, separate from the session transport, and shuts down with the app |
| DM and group calls | Ready | Opcode 13, ring and decline, incoming-call surface; live interoperability unverified |
| Stage channels | Ready | Type 13 recognised, live instance and topic; audience may request to speak, withdraw, accept an invitation and step down; a moderator may start, rename and end a stage and move anybody on or off it |
| Slash commands and components | Ready | Chat-input commands from the channel index, context-menu commands on a message or member, buttons and every select kind, and modals — interaction types 2, 3 and 5 |
| GIF picker | Ready | Trending categories, search with suggestions, sent as a link through Discord's own provider proxy |
| Emoji and sticker picker | Ready | The full unicode catalogue, 1898 emoji in nine CLDR groups with skin-tone variants, alongside the emoji and stickers of every joined server under that server's name; favourites and frecency still lead, and a colon completes across unicode and custom names |
| Emoji, sticker and soundboard uploads | Ready | Emoji, stickers and soundboard sounds are uploaded and deleted from guild settings through the multipart image path, gated on the manage-expressions permission, with limit and file-size refusals said plainly; stickers state their format constraints. A live check of an upload against a joined server is still unverified |
| Soundboard | Ready | Server and default sounds sent into a voice channel, and incoming `VOICE_CHANNEL_EFFECT_SEND` fetched from the CDN and played locally — which is how Discord itself does it, since the sound is never mixed into the RTP stream |
| Video and screen share | Built, wired both ways and self-verified | Share, stop, pause and a viewer count from the voice room; watch somebody else's stream in place of the participant grid. 544 real frames became 2151 encrypted packets and came back as 516 pictures at 1280x720; a second Discord account is the only thing left that can confirm delivery over Discord's own servers; click any tile to put that participant on the stage: their stream while it arrives, otherwise their tile large, including the sender's own preview; a second click or Escape returns to the grid; a stopped watch is withdrawn on Discord's side so the next one is answered; a lost display capture is reopened, and the share ends with a reason if it stays lost |
| Screen share audio | Built, unverified over Discord | The machine's own output captured through WASAPI loopback and sent as Opus on the stream connection's audio SSRC rather than the voice one |
| Camera in a voice channel | Built both ways, unverified over Discord | Media Foundation capture through the same encoder and voice socket as the share; opcode 12 declares the SSRCs and opcode 4 sets `self_video`. Incoming cameras are split off by payload type, attributed by announced SSRC, decoded per sender and drawn in the participant tile |
| User settings | Partial | Both `settings-proto` types read, written and live-updated, every write guarded by `required_data_version`; groups Flucord cannot apply are shown unavailable. The stored rows whose effect is local are now applied: display density, dark sidebar, animated emoji, GIF autoplay and in-app notifications change what is drawn |
| Accessibility dials | Ready | Font scale, zoom and reduced motion take effect immediately and persist; the composer underlines misspelled words against a local word list and sends nothing; the spellcheck switch sits beside the dials |
| Custom themes | Ready | Installed by dropping a file in a folder; Flucord JSON, or a BetterDiscord .theme.css of which the colour variables are read |
| Keybinds | Ready | Eleven actions bound and carried out from the settings page, stored locally as the desktop client does, and fired system-wide through a low-level keyboard hook that reports without swallowing. Capture accepts every key the hook can see, and a code neither table knows becomes the embedder's own key id rather than a dropped binding |
| Screenshots | Ready | Saved as PNG from the same capture path the screen share uses, under a sortable name, with the location reported |
| Clips | Ready | The last thirty seconds of whatever the encoder is producing, muxed to MP4 without re-encoding, saved from a keybind |
| Streamer mode | Ready | All six switches: invite links, the account name, sounds, notifications, the window's presence in a recording, and the overlay; follows Go Live automatically |
| In-game overlay | Partial | A layered click-through window showing who is in the room, over any windowed or borderless-fullscreen game; exclusive fullscreen needs an injected overlay, which this client does not do |
| Conversation summaries | Ready to receive | `CONVERSATION_SUMMARY_UPDATE` folded into a per-channel store and rendered above the timeline; selecting one jumps to the message it starts at; Discord still decides per account whether it sends any |
| Embedded activities, store and Nitro | Not ready | Activities are a separate transport; commerce is outside a chat client's remit |
| ETF Gateway framing | Implemented, not default | Live-checked against a real `HELLO`; a full authenticated `READY` has not been decoded, so the shipped default is JSON |
| zstd-stream Gateway compression | Off by default | Decoder is in place and live-validated, but stays disabled until proven against a full authenticated `READY` |

See [the bundle capability ledger](DISCORD_BUNDLE_COVERAGE.md) for the complete
machine-generated inventory, per-domain status, discovery coverage, and
implementation coverage.

The desktop protocol is private and can change without notice. Matching the
installed client's build profile and headers does not guarantee protocol
stability or account-ban immunity.
