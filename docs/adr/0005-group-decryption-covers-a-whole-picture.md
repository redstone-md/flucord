# Group decryption covers a whole picture, not a packet

The room's group encryption covers one complete picture, not the packets that carry it. The sender encrypts the whole picture and only then cuts the ciphertext into RTP packets, so no single packet is a ciphertext a receiver can decrypt. The receive path therefore runs in a fixed order: reassemble the packets back into a picture, decrypt once, decode. Decrypting per packet cannot work, and it fails silently: every piece is dropped one line above the decoder with no error anywhere, so the symptom is a watcher staring at a black stage with working sound, not a visible fault. That is why this is written down: the failure looks like any other broken watched session, and a later change could move the decryptor back onto individual packets without anything failing loudly.

## Status

Accepted.

## Consequences

- The ordering is part of the receive path, not an implementation detail: reassemble first, group decrypt once per picture, decode last. Nothing between the packets and the picture may decrypt.
- The sender half needs no matching decision. Encrypting the whole picture before packetising it is already what the sending path does.
- Audio is unaffected by this ordering, because one Opus packet carries one whole picture. This is exactly why a broken video path can coexist with working sound for a long time without anybody noticing.
- A picture that will not decrypt is dropped whole rather than raised: a group key that has not reached this client yet is ordinary at the start of a stream, and the next picture usually decrypts. What that looks like from outside is packets arriving and no pictures coming out, so a watcher's diagnostics count packets against pictures rather than waiting for an error.
