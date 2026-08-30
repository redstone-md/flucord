# Self-preview is watched back through Discord

A sender's own picture comes from asking Discord for their own stream key, the same ask a watcher makes, so the preview shows what the room actually receives rather than what the encoder produced. Decoding this client's own encoded frames locally was the alternative: cheaper, always available, and blind to whether a single packet left the machine. Chosen for fidelity, and because one path then serves both the sender and every watcher.

## Status

Accepted. Discord answering a watch on your own key is assumed, not yet observed: the official client draws a sender their own stream, but no public documentation or third-party client confirms how. The first live check with a second account settles it.

## Consequences

- Two connections carry one stream key: the one opened to send and the one opened to watch it back. They cannot be told apart by key, so the router has to remember which session it announced video on.
- Self-preview has nothing to draw until Discord answers the watch with an endpoint, which is seconds after the stream itself is live.
- If Discord refuses a watch on your own key, the failure is logged and surfaced. There is deliberately no local-decode fallback: a fallback would hide a broken round-trip behind a picture that looks perfectly fine.
