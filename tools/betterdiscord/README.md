# Flucord Sniffer (BetterDiscord plugin)

Records what a real Discord client sends and receives on its voice and stream
WebSockets. Flucord's voice and Go Live implementation is reverse engineered,
and when something does not work, a capture of the real client doing the same
thing is the fastest way to see which frame or field differs.

## What it captures

- Every text frame (JSON) on voice, stream, and gateway sockets: opcode,
  sequence number, and a summary of the payload. Long values (key packages,
  commits, welcomes) are truncated to a prefix plus length. Tokens are masked.
- Binary frames (the DAVE MLS messages): opcode, sequence, transition id, and
  the first bytes as hex.
- Socket opens and closes with close codes.

It does not see UDP media traffic. Everything DAVE does over signaling is on
the WebSocket, so this is enough for the protocol layer.

## Install

1. Save `FlucordSniffer.plugin.js` into the BetterDiscord plugins folder:
   `%appdata%\BetterDiscord\plugins`.
2. In Discord: Settings, BetterDiscord, Plugins, enable **Flucord Sniffer**.

## Capture

1. Open DevTools (`Ctrl+Shift+I`) and keep the Console tab open.
2. Do the thing that should be captured: join a voice channel, start a
   Go Live stream, have somebody watch it, for about 30 seconds.
3. In the console run:

   ```js
   __flucordDump()
   ```

   The log is copied to the clipboard (thousands of lines survive there; the
   console itself would truncate them). Paste it wherever it is needed.

   `__flucordClear()` empties the log between runs.

## Notes

- The main gateway socket opens before BetterDiscord loads plugins, so its
  early frames are missing from a capture. Voice and stream sockets open on
  join and are captured from their first frame, which is what matters here.
- Frames also print live in the console with the `[flucord-sniff]` prefix.
