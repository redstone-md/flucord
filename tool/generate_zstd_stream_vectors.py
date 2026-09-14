"""Second-round Zstandard vectors: streaming frames and rejection cases.

The first corpus is dominated by one-shot frames, which set Single_Segment_flag
and therefore never exercise the Window_Descriptor path, unknown content sizes,
or window wrap-around. Discord's Gateway uses exactly those. This script appends
positive streaming vectors and writes a separate negative corpus of frames a
conforming decoder has to reject.
"""
import hashlib
import json
import os
import random
import sys

import zstandard

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
random.seed(0xC0FFEE)

positive = []
negative = []


def text(size):
    words = (
        "the quick brown fox jumps over a lazy dog while discord gateway "
        "dispatches guild member list updates across the socket "
    ).split()
    out = []
    while sum(len(w) + 1 for w in out) < size:
        out.append(random.choice(words))
    return (" ".join(out))[:size].encode("utf-8")


def stream_compress(raw, level=6, checksum=False, window_log=None, chunk=4096):
    """Compress without declaring the content size, like a live producer."""
    if window_log is None:
        kwargs = {
            "level": level,
            "write_checksum": checksum,
            "write_content_size": False,
        }
    else:
        kwargs = {
            "compression_params": zstandard.ZstdCompressionParameters(
                window_log=window_log,
                compression_level=level,
                write_checksum=1 if checksum else 0,
                write_content_size=0,
            ),
        }
    compressor = zstandard.ZstdCompressor(**kwargs).compressobj()
    out = []
    for start in range(0, len(raw), chunk):
        out.append(compressor.compress(raw[start : start + chunk]))
    out.append(compressor.flush(zstandard.COMPRESSOBJ_FLUSH_FINISH))
    return b"".join(out)


def emit_positive(name, raw, compressed, note):
    entry = {
        "name": name,
        "note": note,
        "rawBytes": len(raw),
        "compressedBytes": len(compressed),
        "rawSha256": hashlib.sha256(raw).hexdigest(),
        "hasRawFile": len(raw) <= 4096,
    }
    if entry["hasRawFile"]:
        open(os.path.join(OUT, name + ".raw"), "wb").write(raw)
    open(os.path.join(OUT, name + ".zst"), "wb").write(compressed)
    positive.append(entry)


def emit_negative(name, compressed, note):
    open(os.path.join(OUT, name + ".zst"), "wb").write(compressed)
    negative.append({"name": name, "note": note, "bytes": len(compressed)})


body = text(160 * 1024)
short = text(6 * 1024)

# Unknown content size forces the Window_Descriptor path.
for level in (1, 6, 19):
    emit_positive(
        "stream-l%d" % level,
        body,
        stream_compress(body, level=level),
        "streamed, unknown content size, level %d" % level,
    )

emit_positive(
    "stream-checksum",
    body,
    stream_compress(body, checksum=True),
    "streamed with an xxh64 content checksum",
)
emit_positive(
    "stream-window10",
    body,
    stream_compress(body, window_log=10),
    "streamed with a 1 KiB window, forces wrap-around",
)
emit_positive(
    "stream-window17",
    body,
    stream_compress(body, window_log=17, chunk=777),
    "streamed with unaligned chunks and a 128 KiB window",
)

# Long runs of one byte produce RLE blocks inside a streamed frame.
runs = b"".join(bytes([index % 251]) * 3000 for index in range(40))
emit_positive("stream-rle-blocks", runs, stream_compress(runs, level=9), "RLE blocks in a stream")

# Repetitive structure drives repeat offsets and large offset codes.
structured = b"".join(
    ('{"op":0,"t":"GUILD_MEMBER_LIST_UPDATE","s":%d,"d":{"ops":[{"op":"SYNC","range":[0,99]}]}}' % i).encode()
    for i in range(4000)
)
emit_positive(
    "stream-structured", structured, stream_compress(structured, level=12), "repetitive dispatch stream"
)

# Rejection cases.
good = stream_compress(short)
emit_negative("truncated-header", good[:3], "frame magic cut short")
emit_negative("truncated-body", good[: len(good) // 2], "frame cut mid-block")
emit_negative("reserved-block-type", good[:6] + bytes([good[6] | 0x06]) + good[7:], "reserved block type 3")
emit_negative("bad-magic", b"\x00\x00\x00\x00" + good[4:], "wrong frame magic")

checksummed = bytearray(stream_compress(short, checksum=True))
checksummed[-1] ^= 0xFF
emit_negative("bad-checksum", bytes(checksummed), "content checksum does not match")

reserved_fhd = bytearray(good)
reserved_fhd[4] |= 0x08
emit_negative("reserved-fhd-bit", bytes(reserved_fhd), "reserved frame header bit set")

dictionary = zstandard.ZstdCompressionDict(text(8 * 1024))
with_dict = zstandard.ZstdCompressor(dict_data=dictionary, write_content_size=False).compress(short)
emit_negative("dictionary-id", with_dict, "frame requires an external dictionary")

json.dump(positive, open(os.path.join(OUT, "manifest-stream.json"), "w"), indent=2)
json.dump(negative, open(os.path.join(OUT, "manifest-negative.json"), "w"), indent=2)
print(
    "positive=%d negative=%d bytes=%d"
    % (
        len(positive),
        len(negative),
        sum(e["compressedBytes"] for e in positive) + sum(e["bytes"] for e in negative),
    )
)
