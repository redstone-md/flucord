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
frame reordering). Only one capture can run at a time, refused rather than
queued, which is what makes a double capture of a display impossible. Starting
a share or a camera hands the starter a `VideoCaptureLease`, and only the lease
can pause, retune, ask a keyframe or release what it started (ADR-0007): the
stream controller and the camera controller each hold their own lease and
neither can stop the other's capture. The share and the camera run at the
bitrates the stream quality setting says (2.5 Mbit and 1.2 Mbit by default,
Discord's web-client numbers), kept in the `StreamQualitySettings` object and
changed from the settings window; the hub starts the next capture at it. The
clip buffer follows the hub's frames and writes them out as they were encoded,
so a clip is the recording that was already running. The native lifecycle is
owned by the encoder service: frame buffers are copied before release, the
callback closes only after the capture thread joins, and a finalizer closes a
handle nobody stopped.

A share's size (480p to 1440p) and frame rate (15, 30, 60) are picked from
the menu next to the share button and kept in `StreamQualitySettings` with
the bitrates; the bitrate slider names a 720p30 share and other shapes scale
from it (by pixels, and by frame rate less than proportionally). A pick while
sharing is the hub's to apply: a bitrate alone changes on the running encoder,
a new shape restarts the encoder under the same lease, and the lease reports
what it runs at now. The stream controller retargets the sender's pace on
every report and announces a new shape to Discord; the transport keeps the
RTP clock running forward across the restart.

The share is sent from an isolate of its own, the way Discord runs media on a
thread of its own. One module, the Sender (`GoLiveSender`, implemented by
`GoLiveWireSender`), owns the whole of sending: opened once per sender
endpoint with the connection's credentials, the stream key and the settings
the capture runs at, it dials, announces the share on its own ready, builds
the transport on the announced SSRC (and rebuilds it when a reconnect hands
out a new one), answers retransmission asks and picture-loss indications,
follows the loss the media server reports with the bitrate adapter, gates the
share's sound on readiness, and writes the pace line. `GoLiveMediaIsolate` is
the Sender factory in the app: it hosts each Sender on a worker isolate (the
signalling socket, the DAVE group, the packetiser, the pacer, the transport
cipher and the UDP socket), and the native encoder delivers straight to that
isolate (`VideoFrameSinkControl`; the hub is built with the isolate as its
share frame destination, so no address passes through the application
layer). The main isolate keeps a proxy per Sender that speaks the Sender
interface and nothing else; only what the encoder must do crosses back: a
keyframe a viewer needs, a bitrate the loss allows. The tests run the same
Sender in-process (`InProcessGoLiveMediaPlane`). Which endpoint is the
sender's is decided by the RTC service from the pending own-key watches
(ADR-0001); the stream controller opens the Sender on it with the running
settings, forwards each settings change as a reshape, and asks for the
self-preview when the Sender reports ready. Before the isolate, every stage
from the frame copy to the per-packet AES-GCM ran on the UI isolate, and a
long build or a garbage collection held the send path for hundreds of
milliseconds at a time, which reached the viewer as a freeze followed by a
burst. The worker echoes each frame back to the hub, so the clip buffer keeps
recording a share.

The share's sound is captured from the machine's output (WASAPI loopback),
framed into 20 ms stereo Opus on the main isolate, and handed to the share's
connection, which sends it exactly as a call sends the microphone: encrypted
for the group, on the connection's own audio SSRC, with the speaking state
declared. A viewer hears the game, not the room. Flucord's own output (the
room's voices, notifications) is left out of the capture, as Discord does, so
a viewer who is in the room does not hear themselves come back; that needs
Windows 10 build 20348 or later, and an older build captures the whole
endpoint and logs `golive audio: own sound included`. Each captured block is
handed to Dart in a buffer of its own and released after it is copied,
because the callback is delivered after the capture thread has moved on.

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
the sender: a stall in the encoder or in the media isolate) and `queue <n>`
(the deepest the pacing queue got).

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
