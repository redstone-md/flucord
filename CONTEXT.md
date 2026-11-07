# Flucord

A desktop Discord client. Its domain is the rooms a user sits in and the streams those rooms carry.

## Language

**Room**:
A voice channel or a call, with the participants in it. A DM call is a room without a guild, drawn as a band above the DM's messages.
_Avoid_: channel, call, conference

**Participant**:
Somebody in a room, including this account.
_Avoid_: member, user, peer

**Stream**:
One participant's screen or one of their windows, sent into a room over a connection of its own.
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
One stream this client is receiving, from the ask to the last picture. Somebody else's stream, never this account's own. Decoded only while a tile draws it and the client is not suspended.
_Avoid_: connection, socket, channel

**Self-preview**:
The picture a sender gets of their own stream: the encoder's own output, decoded on the sender's machine onto a texture the interface draws. Not a watched session. Drawn only while its tile is on screen and the window is focused.
_Avoid_: thumbnail, monitor, mirror

**Tile**:
One participant, or one stream, in the room's grid. A participant who sends a stream has two: their own and their stream's.
_Avoid_: card, cell, box

**Stage**:
Where one tile is drawn large and the rest of the room is drawn small in a strip below it. The tile can carry a stream, a self-preview, or only a participant.
_Avoid_: focus view, main view, theatre, spotlight

**Focused**:
The participant, or the stream, whose tile is on the stage. Focusing a stream does not start watching it; that is a separate ask.
_Avoid_: selected, pinned, enlarged, maximized

**Pause**:
A sender holding pictures back while the stream stays up.
_Avoid_: freeze, stop, suspend

**Suspended**:
This client's window is minimized or hidden to the tray: watched sessions go on receiving and draw nothing. A window that is merely behind another still draws them.
_Avoid_: paused, backgrounded, minimized

**Unfocused**:
Another window has the keyboard focus. The self-preview is not decoded while the window is unfocused or suspended; watched sessions are unaffected.
_Avoid_: inactive, background, blurred

**Capture**:
The machine's one source of pictures, a display, one window or a camera. Only one runs at a time.
_Avoid_: source, device, input, recorder

**Picture**:
One complete image a stream carries, from the sender's encoder to the watcher's decoder. Packets carry its pieces.
_Avoid_: frame, access unit, image

**Screen-share audio**:
The sound of what is being shared, travelling with the stream rather than with the room's voice.
_Avoid_: system audio, loopback audio, desktop audio

**Direct message (DM)**:
A conversation outside any server, listed under Direct Messages. It has a list of recipients. A one-to-one DM has exactly one; a group DM has any number.
_Avoid_: private channel (Discord's API name)

**Recipient**:
Somebody a DM is with. Never this account.
_Avoid_: participant, peer, member

**Group DM**:
A DM Discord made as a group. It stays a group when only one other person, or nobody, is left in it. It may have its own name and picture; with no name, it goes by its recipients' names.
_Avoid_: group chat, group channel

**Outgoing message**:
A message this client sent that Discord has not confirmed yet. It shows in the timeline at once, as sending or as failed, under its nonce, until the message Discord echoes with that nonce takes its place.
_Avoid_: pending message, local echo
