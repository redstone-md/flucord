# Decoded video is drawn on a shared texture

A decoder draws each picture on a Direct3D texture that Flutter's engine opens by its shared handle and shows in a `Texture` widget. No pixel passes through Dart. The runner makes the texture: it asks `flucord_video.dll` for a surface on the adapter the engine renders with, registers it as a DXGI shared handle texture, and gives Dart the texture id and the surface's address. Dart opens the decoder on that surface. The decoder decodes on the surface's own device, so a picture is decoded, converted to BGRA and copied into the shared texture without leaving the GPU. Each picture marks a frame available. Dart hears only the texture's size.

This replaces a path where every decoded picture travelled as BGRA through Dart: read back from the GPU, copied in the decoder isolate, sent to the main isolate, and turned into an image with `decodeImageFromPixels`. At 1920x1080 that is 8.3 MB a picture, about 500 MB/s at 60 fps. The v0.0.16 log showed the main isolate stalling for 400 ms at a time and only 5 to 12 pictures a second reaching the self-preview of a 60 fps share. Discord and media players built on Flutter (media_kit, fvp) draw video the same way.

After a dropped access unit, the decoder keeps the last whole picture on the texture until it has decoded an IDR picture. Every picture in between is built on one that is gone. The pixel path did this hold in Dart by timestamp; with no pictures in Dart, the decoder does it.

## Status

Accepted. The self-preview uses it first. Watched streams and cameras still take the pixel path and move to the texture next.

## Consequences

- One texture per open decoder, kept for its life. The engine reopens a texture when its handle changes, so the handle changes only when the picture's size does. The texture shown before a resize stays alive one more picture, so a handle the engine was just given is never freed under it.
- The decoder waits on the GPU before it marks a frame available. The engine draws from a device of its own, and an unfinished copy would show as a torn picture. There is one texture and no keyed mutex, so a picture drawn while the engine reads can still tear. That has not been seen; double buffering would cost the engine a texture reopen per picture.
- The surface has to be on the engine's adapter: a legacy shared handle opens only on the adapter that made it. On a laptop with two GPUs, the decode now runs on whichever one Flutter renders with.
- `flucord_video.dll` is loaded by the runner at run time, not linked. Windows editions without Media Foundation still start, and a texture asked for there is refused with the reason, which the tile shows as an unavailable preview.
- A decoder that cannot decode on the GPU still draws on the texture: it uploads the picture it decoded on the CPU.
