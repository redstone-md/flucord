# Self-preview decodes the encoder's own output

A sender's own picture is the encoder's access units decoded on the same machine, drawn on the sender's tile. Watching the stream back through Discord was the first design: the same ask a watcher makes, so the preview would show what the room receives. Live, Discord never answers a `STREAM_WATCH` on the sender's own key (no `STREAM_CREATE`, no `STREAM_SERVER_UPDATE`, no error), while a watch on anybody else's key is answered within half a second, so that design drew nothing and could not tell anybody why.

## Status

Accepted. Supersedes the watched-back design of 2026-08. Whether the official client draws its own preview locally is not documented; what is observed is that the watch-back path is dead.

## Consequences

- One connection carries one stream key, the sender's. An own-key endpoint is always the sender's, and nothing about the ask has to be remembered to tell the roles apart.
- The preview is up as soon as the encoder produces a keyframe, before Discord has answered the create.
- The preview shows what left the encoder, not what left the machine. Whether pictures reach the room is the Sender's pace line and the viewer count, not the tile.
- The cap on watched sessions is for other people's streams only; the sender's own no longer takes a seat (ADR-0002).
- Decoding the preview costs a decoder while sharing, on the sender's machine, and it is not suspended with the window (ADR-0003 covers watched sessions only).
