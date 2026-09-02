# Flucord

A desktop Discord client. Its domain is the rooms a user sits in and the streams those rooms carry.

## Language

**Room**:
A voice channel or a call, with the participants in it. A DM call is a room without a guild.
_Avoid_: channel, call, conference

**Participant**:
Somebody in a room, including this account.
_Avoid_: member, user, peer

**Stream**:
One participant's screen, sent into a room over a connection of its own.
_Avoid_: share, screen share, broadcast, go-live

**Stream key**:
How a stream is addressed: the room and the sender, never a server-assigned id.
_Avoid_: stream id, stream name, stream url

**Sender**:
The participant whose stream it is, and the only one capturing it.
_Avoid_: broadcaster, host, sharer, streamer

**Watcher**:
A participant receiving somebody else's stream.
_Avoid_: viewer, spectator, audience

**Watched session**:
One stream this client is receiving, from the ask to the last picture. Somebody else's stream, never this account's own.
_Avoid_: connection, socket, channel

**Self-preview**:
The picture a sender gets of their own stream: the encoder's own output, decoded on the sender's machine. Not a watched session.
_Avoid_: thumbnail, monitor, mirror

**Stage**:
Where one stream is drawn large, in place of the participant grid.
_Avoid_: focus view, main view, theatre, spotlight

**Pause**:
A sender holding pictures back while the stream stays up.
_Avoid_: freeze, stop, suspend

**Suspended**:
This client's window is not in the foreground: watched sessions go on receiving and draw nothing.
_Avoid_: paused, backgrounded, minimized

**Capture**:
The machine's one source of pictures, a display or a camera. Only one runs at a time.
_Avoid_: source, device, input, recorder

**Picture**:
One complete image a stream carries, from the sender's encoder to the watcher's decoder. Packets carry its pieces.
_Avoid_: frame, access unit, image

**Screen-share audio**:
The sound of what is being shared, travelling with the stream rather than with the room's voice.
_Avoid_: system audio, loopback audio, desktop audio
