# Native media

Opening a voice channel initializes the native Windows WebRTC media layer. The
voice surface supports microphone mute, input/output device selection,
screen/window source selection, live desktop-capture preview, and deterministic
track teardown. This path uses native WebRTC textures and devices, not a WebView.

Inline message video uses `media_kit` with the packaged Windows native video
libraries and a Flutter texture. Discord CDN URLs are opened as issued, without
bot authorization, personal tokens, fingerprints, private client headers, or a
WebView. Player resources and stream subscriptions are released when their
message leaves the widget tree.

Voice-message audio uses the same packaged native media runtime without a video
texture. Discord's sampled waveform is decoded locally into a compact seek
surface, while the attachment duration keeps stable timeline geometry before
media probing completes.

For Discord repositories, Flucord performs the documented main Gateway
voice-state exchange, Voice Gateway v8 heartbeat and resume flow, UDP address
discovery, AEAD mode negotiation, and DAVE MLS signaling through the bundled
official `libdave.dll`. The voice surface reports joining, connection,
discovery, DAVE negotiation, reconnect, failure, and encrypted transport-ready
states. Mute changes use a voice-state update without rebuilding the session.

Encrypted transport readiness activates a native audio uplink. Flucord captures
48 kHz stereo PCM16 without a browser runtime, frames it into 20 ms packets,
encodes Opus with bundled native libopus, applies DAVE and RTP, then sends it
through Discord's AES-256-GCM or XChaCha20-Poly1305 RTP-size UDP transport. Mute
and disconnect finish the speaking burst before tearing down the microphone.

The receive boundary maps speaking SSRCs to users, reorders RTP across sequence
wrap, rejects duplicate/replayed packets, decrypts DAVE, and keeps independent
Opus decoder state per remote user. Bounded loss uses native Opus PLC/FEC; long
gaps reset only the affected decoder. Decoded PCM plays through per-user native
SoLoud streams with a 60 ms playout buffer and live output-device switching.

The media path is implemented end to end, but real Discord interoperability
still needs verification in an actual bot voice session before production-ready
calls can be claimed. Discord's public bot voice contract documents Opus audio
transport but no outbound screen-video payload, so screen capture remains a
local preview and is not sent to Discord.
