# A watched session recovers a lost packet before it asks for a keyframe

A lost packet on a watched session is asked for again (RTCP NACK) at once and then once per round trip, and the picture it belongs to waits for the answer for a bounded time: twice the measured round trip, no less than 100 ms and no more than 500 ms. Only when that window closes without the packet is the picture closed without it, and only then may the session ask the sender for a keyframe (RTCP PLI). A keyframe ask that arrives while a hole is still inside its window is held and paid when the last hole closes. Keyframe asks are rate limited to one a second per stream.

The alternative this replaces was a reorder window counted in packets (eight, about one picture at 60 fps) with the keyframe ask sent as soon as a picture failed to open. The retransmission then arrived after the buffer had moved on, and every hole cost a keyframe. The sender is the official Discord client, whose encoder answers every keyframe ask with an IDR picture; a stream of IDR pictures at a fixed bitrate raises the quantiser, and its quality scaler answers that by lowering resolution and frame rate. The watcher saw a stream that started at 1080p and ended at 720p with stutter on every hiccup, and the log of one day held 394 keyframe asks.

The round trip is measured on the voice heartbeat that already exists (opcode 3 to opcode 6); no probe is added. The window and the ask interval are expressed in time, so they mean the same thing at 15 and at 60 fps. Audio keeps its count-based window: a late audio packet is worth nothing.

The same connection rule covers the retransmission stream itself. A packet on a retransmission SSRC is only ever restored into its original's place or dropped; it never opens a reorder buffer under its own SSRC, because nothing useful can come back from asking the server to resend that stream's own sequence numbers.

## Status

Accepted.

## Consequences

- The receive path holds packets behind a hole for up to half a second. A stream with steady loss carries that much more latency than one without, which is the price of not asking for a keyframe.
- A hole is asked for the moment a packet lands past it. There is no first-ask delay to trade against.
- The reorder buffer and the retransmission asks belong to the connection, not to a subscriber (one packet pipeline per gateway client). Suspension (ADR-0003) lets go of the decoder and the picture receiver; the buffer and the asks stay with the connection.
- Nothing decrypts before reassembly (ADR-0005). The wait for a retransmission happens before reassembly closes the picture.
- The broken-references verdict lives in the watched session pipeline that owns the picture receiver, fed alike by a picture that will not decrypt, a pacer overflow with no keyframe queued, and a decoder drop; the gateway client's gate on when the ask may leave is unchanged.
- The pacer treats a slot too far in the future as a clock jump and re-anchors on it, and an overflow keeps the newest keyframe it holds. Neither asks the sender for anything; only a queue with no keyframe in it does.
- The room is redrawn when a stream starts or stops, not per picture. The pictures travel on the stream's own picture stream.
- Not decided here: receiver reports and bandwidth estimation feedback to the media server, and the sender side (pacing, bitrate adaptation, keyframe answering).
