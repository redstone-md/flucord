# A capture is held by a lease

Starting a capture (a display for a stream, or a camera) hands the starter a lease, and only that lease can pause the capture, change its bitrate, ask it for a keyframe, or stop it. The capture hub keeps the one running lease; a lease that is not the running one does nothing, and releasing twice is harmless. A quality change while a stream's lease is live is the hub's to apply: a bitrate alone is set on the running encoder, a new size or frame rate restarts the encoder under the same lease, and the lease reports what it runs at now.

The alternative this replaces enforced "only one capture" at start and nowhere else. Stop, pause, bitrate and keyframe were open to anyone holding the hub, so the stream controller and the camera controller each kept a flag saying "the running capture is mine", each with a comment explaining why it must not stop what the other started. The quality change crossed three modules: the settings controller wrote the hub, the composition listened to the settings controller and called the stream controller, and the stream controller chose between a bitrate change and a restart. The isolate's native frame sink address travelled from the media plane through the stream controller into the hub.

## Status

Accepted.

## Consequences

- The ownership rule is the type. No controller carries a flag or a comment about whose capture is running. The stream controller and the camera controller shrink to lease, use, release.
- The hub is built with the share's frame destination (the media isolate) and routes a stream's frames to it and the echoed frames back to its own frame stream. The application layer never sees the native address. The domain interface still names it as an integer, as `VideoFrameSinkControl` did before.
- The hub serialises what it asks of the encoder: a release cannot overtake a restart that is half way through.
- Every settings change is reported, a bitrate change included, because the sender's pace has to follow the bitrate even when nothing needs announcing. The stream controller announces to Discord only when the shape changed.
- An encoder that refuses a bitrate is logged once per lease by the hub.
- A restart the encoder refuses is reported as an error on the lease, and the lease is over: nothing runs, so the hub is free for the next capture. The stream stays up with no capture behind it; ending it is the user's call, as before.
- The RTP clock across a restart is the transport's concern, unchanged: a new encoder counts from zero and the transport puts its first picture one frame after the last one sent.
- One fake encoder under test support serves every capture test.
