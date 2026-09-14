# libdave Windows binary

This directory contains the official Discord `libdave.dll` built from commit
`52cd56dc550f447fb354b3a06c9e2d2e2a4309c6`.

- Upstream: <https://github.com/discord/libdave>
- License: MIT, reproduced in `LICENSE`
- Target: Windows x64, Release
- Dependencies: OpenSSL 3 and MLS++ linked statically
- MSVC runtime: static (`/MT`)
- SHA-256: `D08EE797B0DE5F825BA936276A15089DC169139485195034AE91537F9EE21CE0`

Run `powershell -ExecutionPolicy Bypass -File tool/build_libdave.ps1` from the
repository root to rebuild and replace the binary.
