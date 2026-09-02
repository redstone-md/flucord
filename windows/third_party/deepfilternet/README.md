# DeepFilterNet Windows binary

This directory contains libDF, the DeepFilterNet runtime, built as `df.dll`
from commit `d375b2d8309e0935d165700c91da9de862a99c31`, with the
DeepFilterNet3 ONNX model it runs (`DeepFilterNet3_onnx.tar.gz`, 48 kHz,
10 ms hops, 20 ms of lookahead).

- Upstream: <https://github.com/Rikorose/DeepFilterNet>
- License: MIT (the crate is MIT/Apache-2.0), reproduced in `LICENSE`
- Target: Windows x64, Release, `--no-default-features --features capi` with
  `default-model` dropped from the `capi` feature (the C API takes a path, so
  the embedded copy of the model was dead weight), fat LTO, one codegen unit,
  stripped
- Inference: tract (pure Rust), no ONNX Runtime
- MSVC runtime: static (`+crt-static`)
- SHA-256: `00782A2178D8ED2DA917973E16B09364B9466AA08FAC3A299CB2D6D5536F2DB3`

Run `powershell -ExecutionPolicy Bypass -File tool/build_deepfilternet.ps1`
from the repository root to rebuild and replace the binary.
