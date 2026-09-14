# The microphone is cleaned between the framer and the encoder

Noise suppression runs on the 20 ms PCM frames the audio pipeline already cuts for Opus, after the framer and before the encoder, and nowhere else. The filter is DeepFilterNet (MIT) through libDF's C API, bundled as `df.dll` with the DeepFilterNet3 model beside the executable; a build without it hides the switch. The switch is a machine setting, kept in a file beside the stream quality and off by default. The model is mono: a stereo frame is downmixed for it and the cleaned signal is written to both channels.

The issue named the capture service's byte handler as the insertion point. That handler sees chunks of whatever size the driver delivers, so a filter there would have to keep its own 10 ms buffer, adding up to a hop of latency and a second framer. The pipeline's frames are two hops exactly, so the filter there adds no buffering at all. Running the model per channel was considered and rejected: a Discord call is heard in mono, and the CPU would double for a difference nobody hears.

## Status

Accepted.

## Consequences

- `VoiceNoiseSuppressor` is the domain seam (`hopSize`, `process(frame, channels:)`, `dispose`), opened through a `Future` factory. Loading the model takes the better part of a second, so the pipeline opens it when the switch goes on, off the frame path (the data class runs the load on a worker isolate); frames pass through as captured until it is ready. A suppressor that fails to open or to run is dropped, reported once, and the pipeline's switch reads off, which is what the settings switch shows; switching on again is the retry.
- With the switch off the bytes reaching the encoder are the captured bytes; the fake suppressor in the tests proves it.
- When the uplink goes quiet (mute, push to talk released) two frames of silence are pushed through the model and sent before the speaking burst ends, so the 29 ms of a word still inside the model come out and the model holds silence for the next press rather than that tail.
- Measured on this machine (Windows 11, the test suite's own run, one thread): a 20 ms stereo frame takes about 2 ms to clean (4 ms at worst), so the filter costs about a tenth of one core while in a call and nothing while muted or out of one. The model's own delay, an STFT window over the hop plus two hops of lookahead, measured as 29 ms from a sound entering to it leaving; the pipeline adds no buffering on top. The bundle grows by 25 MB: a 17 MB DLL (tract, the pure-Rust inference runtime; the build drops upstream's embedded copy of the model, which the C API never reads) and the 8 MB model file.
- The filter runs on the main isolate with the encoder, as the whole microphone path does today. If a long build stalls it, the answer is the same one the stream took: the microphone path moves to a worker, not the filter alone.
- libDF aborts the process on a model it cannot read rather than returning an error, so the archive is decoded in Dart before the library is asked to load it: a truncated model is a caught error, not a crash on every call.
- Whether the switch is offered is decided by probing the bundle (model present, library loads), not by the platform.
- macOS and Linux follow the same FFI path once their `libdf` is built; nothing in the Dart side is Windows-specific but the file name.
