# Native media

A voice channel offers two surfaces on one channel id, chosen from a switch in
the channel header: the voice room and the ordinary message timeline that
Discord hangs off the same channel. Only the room initializes the native Windows
WebRTC media layer, so a channel opened from a mention, a jump-to-message, or the
inbox lands on the chat and never reaches for a device.

The room surface supports microphone mute and input/output device selection,
using native WebRTC devices rather than a WebView. Screen capture is not part of
it: the machine's display is captured by one module, described below, and a
second capture path is exactly what used to refuse a share outright.

One capture and encode module owns the machine's video. `VideoCaptureHub` wraps
the single native encoder behind `flucord_video.dll` (Desktop Duplication into a
Media Foundation H.264 encoder, run in low-latency mode so no picture waits on
frame reordering), and anyone who wants local pictures attaches to it: a Go Live
share, the camera, the clip buffer. Only one capture can run at a time, refused
rather than queued, which is what makes a double capture of a display impossible.
The share and the camera run at the bitrates the stream quality setting says
(2.5 Mbit and 1.2 Mbit by default, Discord's web-client numbers), kept in the
`StreamQualitySettings` object and changed from the settings window; a capture
that is already running keeps what it started with, and the next one takes
whatever the setting says then. The clip buffer follows the module's frames and
writes them out as they were encoded, so a clip is the recording that was already
running. The native lifecycle is owned by the encoder service: frame buffers are
copied before release, the callback closes only after the capture thread joins,
and a finalizer closes a handle nobody stopped.

The capture runs on a fixed tick at the configured frame rate (any rate: the
tick is one over it): sleep until the tick on a high-resolution timer, take
whatever the desktop shows right then, encode it, and repeat the last picture
when nothing moved. The schedule is absolute, so a frame's own convert and
encode time does not push the next tick later. The `golive pace` log line
prints each stage per frame; on a loop keeping pace, wait + convert + encode
adds up to one frame interval.

Between the encoder and the socket, `DiscordVideoStreamTransport` paces a
picture's packets onto the wire at 2.5 times the encoder bitrate instead of in
one burst (WebRTC's pacer, in short): ten packets for a picture and a hundred
for a keyframe, sent in one loop, overflow the uplink's queue, and the packets
it drops are the loss the media server reports back. Retransmissions skip the
queue.

The share's bitrate follows that loss. Each receiver report goes through
`StreamBitrateAdapter` (WebRTC's loss-based rule: back off in proportion to
loss above 10%, creep back 8% per clean report, hold in between, never below
a fifth of the target); a change goes to the running encoder
(`flucord_video_set_bitrate`, applied from the next picture) and to the pacer.
An encoder that refuses to change rate is logged once and keeps its rate; the
pacer follows regardless. The pace log then reads `bitrate 1800k` while
adapted, and always `gap <ms>` (the longest wait between two pictures reaching
the transport: a stall in the encoder or in this isolate) and `queue <n>` (the
deepest the pacing queue got).

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
transport; outbound video rides the Go Live stream connection and the camera's
voice-connection SSRCs instead, both fed by the capture module above.
