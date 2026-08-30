# The viewer holds several watched sessions

The viewer was built around one stream at a time and is reshaped around a map of them, capped at four, because Discord's own client lets a participant watch several streams at once and self-preview adds one more to whatever is already being watched. The cap is ours and not Discord's: no limit is documented anywhere, and each session costs a decoder and a connection of its own.

## Status

Accepted.

## Consequences

- The multistream interface is not part of this. Sessions can exist before the room can draw more than one on the stage, and the grid arrives later.
- Sharing and watching at the same time is allowed. The capture that feeds a stream and the decoders that receive one are separate resources, so one client can hold both.
- A sender's own session counts towards the cap like anybody else's.
