# A suspended client keeps receiving

When this client's window is not in the foreground, watched sessions stop drawing and keep their connections: what feeds the decoder is dropped, the decoder is let go, and nothing is torn down on Discord's side. Sending is never affected by suspension. The obvious alternative, dropping the connection until the window is back, was rejected because reopening it costs a handshake and a fresh keyframe, and because a sender's stream must not stutter just because they looked at another window.

## Status

Accepted.

## Consequences

- Suspending is not pausing. A sender who pauses stops pictures for everybody; a suspended client stops pictures only for itself.
- Resuming reattaches a decoder, so the first picture back can be a moment behind until the next keyframe.
