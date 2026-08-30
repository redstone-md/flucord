# Screen-share audio reuses the voice receive path

The sound of a shared screen travels on the stream connection, not on the room's voice connection, and this client was dropping it on the floor: a stream session listened for pictures and ignored everything else. It is received through the same transport and decode path the call's own audio already uses, with that path's receiving half extracted so a stream can use it without also owning a microphone.

## Status

Accepted.

## Consequences

- Every watched stream gets a decoder of its own, keyed by the sender, exactly as the call's audio is keyed by participant.
- A stream's sound ends with its session. Watching is what gives it somewhere to play, so stopping a watch stops the sound.
- Per-stream volume is out of scope for now; streams play at the room's level.
- Receiving audio on a stream connection was never exercised end to end, so the wire format is assumed to be the room's own: Opus at 20 ms on the stream's audio SSRC, under whatever group cipher the room negotiated.
