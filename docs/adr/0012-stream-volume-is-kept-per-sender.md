# Stream volume is kept per Sender

A Stream's sound used to play at the Room's level, so a loud game drowned out the voices and the only way to quiet it was to stop watching. Each Stream now has a level of its own, from 0 to 100 %, and a mute, set from the Stream menu. Both are local to this client and saved in the listening settings next to the participant levels.

The level is keyed by the Sender, not by the playback source. A Watched session's source id is new for every session (`stream:<stream key>:<n>`), so a level keyed by source id would be lost the next time the same person streams. The source id is built and read back in one place, next to the Stream key, so the Sender is never guessed from the numbers in it.

## Status

Accepted. Replaces the line in ADR-0004 that put per-Stream volume out of scope.

## Consequences

- The voice controller notes each Stream source on its first frame and sets it to the Sender's level before the frame plays, so a session never starts with a moment at full level. It keeps the live sources of each Sender until their sound ends, so a new level reaches a session that is already playing.
- Muting a Stream sets its sources silent and keeps the level, so unmuting brings the chosen level back. The picture is not touched.
- The Sender's voice is a separate source with its own participant level and mute. A Stream level never changes it, and a participant level never changes the Stream.
- Full level is not stored, the same rule as for participants. A Stream above 100 % is out of scope.
