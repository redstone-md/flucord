# A suspended client keeps receiving

When this client's window has nothing on screen, watched sessions stop drawing and keep their connections: what feeds the decoder is dropped, the decoder is let go, and nothing is torn down on Discord's side. Sending is never affected by suspension. The obvious alternative, dropping the connection until the window is back, was rejected because reopening it costs a handshake and a fresh keyframe, and because a sender's stream must not stutter just because they looked at another window.

## Amendment (2026-09-01): the screen decides, not the focus

Suspension used to follow the focus, so a viewer who alt-tabbed away had their picture stop and restart on every glance at another window. Each restart cost a fresh receiver and a wait for the next keyframe, which reads as the stream breaking. The rule now follows the screen instead: a window that is still visible keeps drawing when it loses the focus, and only a window nothing of is on screen (minimized, or hidden to the tray) suspends. The chat's read state still follows the focus.

## Status

Accepted.

## Consequences

- Suspending is not pausing. A sender who pauses stops pictures for everybody; a suspended client stops pictures only for itself.
- Resuming reattaches a decoder, so the first picture back can be a moment behind until the next keyframe.
- Losing the focus does not suspend. A watched stream keeps playing behind another window.
