"""Generate reference Zstandard vectors for Flucord's Dart decoder.

Every vector pairs a compressed frame with its exact expected plaintext, so the
Dart decoder can be checked against libzstd 1.5.7 without shipping a native
dependency.
"""
import hashlib
import json
import os
import random
import struct
import sys

import zstandard

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

random.seed(0x5EED)
manifest = []


INLINE_LIMIT = 4096


def emit(name, raw, compressed, note):
    """Store the frame plus a digest of its plaintext.

    Small plaintexts are kept verbatim so a failing decode is debuggable; large
    ones are represented only by length and SHA-256 to keep the fixtures small.
    """
    entry = {
        "name": name,
        "note": note,
        "rawBytes": len(raw),
        "compressedBytes": len(compressed),
        "rawSha256": hashlib.sha256(raw).hexdigest(),
        "hasRawFile": len(raw) <= INLINE_LIMIT,
    }
    if entry["hasRawFile"]:
        with open(os.path.join(OUT, name + ".raw"), "wb") as handle:
            handle.write(raw)
    with open(os.path.join(OUT, name + ".zst"), "wb") as handle:
        handle.write(compressed)
    manifest.append(entry)


def compress(raw, level=3, checksum=False, content_size=True, threads=0):
    params = zstandard.ZstdCompressor(
        level=level,
        write_checksum=checksum,
        write_content_size=content_size,
        threads=threads,
    )
    return params.compress(raw)


def text(size):
    words = (
        "the quick brown fox jumps over a lazy dog while discord gateway "
        "dispatches guild member list updates across the socket "
    ).split()
    out = []
    while sum(len(w) + 1 for w in out) < size:
        out.append(random.choice(words))
    return (" ".join(out))[:size].encode("utf-8")


def json_like(count):
    rows = []
    for index in range(count):
        rows.append(
            '{"id":"%018d","type":%d,"name":"channel-%d","nsfw":false,'
            '"position":%d,"parent_id":null}' % (index, index % 16, index, index)
        )
    return ("[" + ",".join(rows) + "]").encode("utf-8")


# 1. Degenerate inputs.
emit("empty", b"", compress(b""), "zero-length content")
emit("single-byte", b"A", compress(b"A"), "one raw literal")
emit("short-raw", b"flucord", compress(b"flucord"), "incompressible short input")

# 2. RLE and long matches.
emit("rle-1k", b"\x5a" * 1024, compress(b"\x5a" * 1024), "single repeated byte")
emit("rle-long", b"ab" * 20000, compress(b"ab" * 20000), "two-byte cycle, long matches")
repeated = (b"GUILD_MEMBER_LIST_UPDATE" * 2048)
emit("repeat-token", repeated, compress(repeated), "repeated token, repeat offsets")

# 3. Random data forces raw literals and raw blocks.
noise = bytes(random.getrandbits(8) for _ in range(24 * 1024))
emit("random-24k", noise, compress(noise), "incompressible, raw blocks")
emit("random-24k-l19", noise, compress(noise, level=19), "incompressible at level 19")

# 4. Natural text at several levels exercises Huffman literals and FSE tables.
body = text(48 * 1024)
for level in (1, 3, 9, 19, 22):
    emit("text-l%d" % level, body, compress(body, level=level), "english text level %d" % level)

# 5. Structured payloads close to real Gateway dispatches.
payload = json_like(800)
emit("json-l3", payload, compress(payload), "json-like structure")
emit("json-l19", payload, compress(payload, level=19), "json-like at level 19")

# 6. Header variations.
emit("checksum", body[:8192], compress(body[:8192], checksum=True), "xxh64 content checksum")
emit(
    "no-content-size",
    body[:8192],
    compress(body[:8192], content_size=False),
    "frame header without content size",
)

# 7. Explicitly small window forces window wrap-around during decode.
small_window = zstandard.ZstdCompressor(
    compression_params=zstandard.ZstdCompressionParameters(
        window_log=10, compression_level=6
    )
)
emit("small-window", body, small_window.compress(body), "window_log=10, wrapping window")

# 8. Multiple frames concatenated in one buffer.
emit(
    "multi-frame",
    body[:4096] + body[4096:8192],
    compress(body[:4096]) + compress(body[4096:8192]),
    "two frames back to back",
)

# 9. Skippable frame before real content.
skippable = struct.pack("<II", 0x184D2A50, 8) + b"flucord!"
emit(
    "skippable-frame",
    body[:4096],
    skippable + compress(body[:4096]),
    "skippable frame then content",
)

# 10. Streaming frame with explicit flushes: the Discord gateway shape.
chunker = zstandard.ZstdCompressor(level=6, write_checksum=False)
stream_chunks = []
stream_raw = b""
compressor = chunker.compressobj()
for index in range(12):
    piece = (
        '{"t":"MESSAGE_CREATE","s":%d,"op":0,"d":{"content":"chunk %d %s"}}'
        % (index, index, "padding" * (index + 1))
    ).encode("utf-8")
    stream_raw += piece
    stream_chunks.append(compressor.compress(piece) + compressor.flush(zstandard.COMPRESSOBJ_FLUSH_BLOCK))
stream_chunks.append(compressor.flush(zstandard.COMPRESSOBJ_FLUSH_FINISH))
emit(
    "stream-flushed",
    stream_raw,
    b"".join(stream_chunks),
    "one frame, flushed per message like compress=zstd-stream",
)
with open(os.path.join(OUT, "stream-flushed.chunks.json"), "w", encoding="utf-8") as handle:
    json.dump([len(chunk) for chunk in stream_chunks], handle)

# 11. Content larger than a single 128 KiB block.
big = text(300 * 1024)
emit("text-multiblock", big, compress(big, level=6), "multiple compressed blocks")

with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)

total = sum(entry["compressedBytes"] for entry in manifest)
print("vectors=%d compressedTotalBytes=%d" % (len(manifest), total))
