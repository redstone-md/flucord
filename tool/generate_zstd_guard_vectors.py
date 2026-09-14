"""Hand-built Zstandard frames that reach one decoder guard each.

The conformance corpora only contain frames libzstd chose to emit, so every
malformed-input guard in `lib/src/data/zstd` stayed unexecuted: no compressor
produces a bad FSE accuracy log, an oversized Huffman weight, or a match that
reaches before the start of a frame. Random mutation does not get there either,
because most of those guards need a frame whose *earlier* fields are all valid.

So every frame here is built field by field to trip exactly one check, and the
manifest records the message that check must produce. A fixture that starts
failing somewhere else — say, because a bounds test moved earlier — shows up as
a message mismatch rather than as a still-green test.

The legal frames in the positive manifest are checked against the reference
decompressor before they are written; the illegal ones record whether the
reference rejects them too, which is the cross-check that the frame really is
malformed and not merely unusual.
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

MAGIC = 0xFD2FB528
RAW, RLE, COMPRESSED, RESERVED = 0, 1, 2, 3
MAX_BLOCK = 128 * 1024

positive = []
reject = []


# --------------------------------------------------------------------------
# Frame and block scaffolding.
# --------------------------------------------------------------------------
def block(last, kind, size, body=b""):
    header = (size << 3) | (kind << 1) | (1 if last else 0)
    return struct.pack("<I", header)[:3] + body


def header(
    *,
    window_log=10,
    single_segment=False,
    content_size=None,
    content_width=None,
    checksum=False,
    dictionary_id=None,
    dictionary_width=0,
    reserved=False,
):
    """Builds Magic | FHD | Window_Descriptor | Dictionary_ID | Content_Size."""
    flag, field = 0, b""
    if content_size is not None:
        if content_width is None:
            content_width = 1 if content_size < 256 else 4
        assert content_width != 1 or single_segment, "1 byte size needs one segment"
        flag = {1: 0, 2: 1, 4: 2, 8: 3}[content_width]
        stored = content_size - 256 if content_width == 2 else content_size
        field = (stored & ((1 << (8 * content_width)) - 1)).to_bytes(
            content_width, "little"
        )
    descriptor = flag << 6
    descriptor |= 0x20 if single_segment else 0
    descriptor |= 0x08 if reserved else 0
    descriptor |= 0x04 if checksum else 0
    descriptor |= {0: 0, 1: 1, 2: 2, 4: 3}[dictionary_width]
    out = struct.pack("<I", MAGIC) + bytes([descriptor])
    if not single_segment:
        out += bytes([(window_log - 10) << 3])
    if dictionary_width:
        out += dictionary_id.to_bytes(dictionary_width, "little")
    return out + field


def frame(blocks, **kwargs):
    return header(**kwargs) + b"".join(blocks)


def compressed_frame(body, before=(), window_log=10, last=True):
    """Wraps one hand-built compressed block, optionally after seed blocks."""
    return frame(
        list(before) + [block(last, COMPRESSED, len(body), body)],
        window_log=window_log,
    )


def seed_block(payload):
    return block(False, RAW, len(payload), payload)


# --------------------------------------------------------------------------
# Bitstream writers, mirroring the two readers in zstd_bit_reader.dart.
# --------------------------------------------------------------------------
class ForwardBits:
    """Little-endian, least significant bit first: the FSE count header."""

    def __init__(self):
        self.bits = []

    def add(self, value, count):
        self.bits.extend((value >> index) & 1 for index in range(count))

    def to_bytes(self):
        out = bytearray((len(self.bits) + 7) // 8)
        for index, bit in enumerate(self.bits):
            if bit:
                out[index >> 3] |= 1 << (index & 7)
        return bytes(out)


def reverse_stream(bits):
    """Packs entropy bits so the reverse reader sees them in order.

    Bit 0 of the stream is the top bit of the *last* byte; the padding marker is
    the highest set bit of that byte, so the byte count follows from the payload.
    """
    total = len(bits)
    size = (total + 8) // 8
    padding = 8 * size - total
    assert 1 <= padding <= 8
    out = bytearray(size)

    def put(index, value):
        if value:
            out[size - 1 - (index >> 3)] |= 1 << (7 - (index & 7))

    put(padding - 1, 1)
    for offset, bit in enumerate(bits):
        put(padding + offset, bit)
    return bytes(out)


def bit_list(*fields):
    """Flattens (value, width) pairs into most-significant-bit-first bits."""
    bits = []
    for value, width in fields:
        bits.extend((value >> index) & 1 for index in range(width - 1, -1, -1))
    return bits


def fse_count_header(counts, accuracy_log):
    """Encodes a normalized distribution the way readZstdFseTable decodes it."""
    writer = ForwardBits()
    writer.add(accuracy_log - 5, 4)
    remaining = (1 << accuracy_log) + 1
    threshold = 1 << accuracy_log
    width = accuracy_log + 1
    for count in counts:
        assert count != 0, "zero counts would need a run length escape"
        value = count + 1
        ceiling = (2 * threshold - 1) - remaining
        if value < ceiling:
            writer.add(value, width - 1)
        elif value < threshold:
            writer.add(value, width)
        else:
            writer.add(value + ceiling, width)
        remaining -= abs(count)
        while remaining < threshold:
            width -= 1
            threshold >>= 1
    assert remaining == 1, "distribution must fill the table exactly"
    return writer.to_bytes()


# --------------------------------------------------------------------------
# Literals and sequence section builders.
# --------------------------------------------------------------------------
def literals_raw(payload):
    """Raw_Literals_Block, one byte header."""
    assert len(payload) <= 31
    return bytes([(len(payload) << 3) | 0]) + payload


def literals_rle_wide(value, regenerated):
    """RLE_Literals_Block with the three byte header (Size_Format 3)."""
    head = 1 | (3 << 2) | ((regenerated & 0x0F) << 4)
    return bytes(
        [head, (regenerated >> 4) & 0xFF, (regenerated >> 12) & 0xFF, value]
    )


def literals_head(kind, size_format, regenerated, compressed):
    """Header of a Huffman coded literals section."""
    width = {2: 4, 3: 5}.get(size_format, 3)
    shift = {3: 10, 4: 14, 5: 18}[width]
    packed = kind | (size_format << 2) | (regenerated << 4) | (compressed << (4 + shift))
    return packed.to_bytes(width, "little")


def sequence_section(count, modes, tables=b"", stream=b""):
    if count < 128:
        head = bytes([count])
    elif count < 0x7F00:
        head = bytes([(count >> 8) + 128, count & 0xFF])
    else:
        head = bytes([255]) + struct.pack("<H", count - 0x7F00)
    return head + bytes([modes]) + tables + stream


RLE_MODES = (1 << 6) | (1 << 4) | (1 << 2)


def rle_sequences(count, literal_code, offset_code, match_code, bits):
    """A sequence section whose three tables are all RLE, so states cost 0 bits."""
    return sequence_section(
        count,
        RLE_MODES,
        bytes([literal_code, offset_code, match_code]),
        reverse_stream(bits),
    )


# --------------------------------------------------------------------------
# Emitters.
# --------------------------------------------------------------------------
def emit_positive(name, raw, compressed, note):
    decoded = zstandard.ZstdDecompressor().decompress(
        compressed, max_output_size=1 << 24
    )
    assert decoded == raw, "%s: reference decoder disagrees" % name
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


def emit_reject(name, compressed, note, expect, stream_expect=None):
    """Records a frame that must be rejected, and the message it must produce.

    [stream_expect] is what the incremental decoder says instead; truncation is
    not an error until the producer closes the stream, so those cases surface as
    a `finish()` complaint rather than as the one-shot message.
    """
    try:
        zstandard.ZstdDecompressor().decompress(compressed, max_output_size=1 << 24)
        reference_rejects = False
    except zstandard.ZstdError:
        reference_rejects = True
    open(os.path.join(OUT, name + ".zst"), "wb").write(compressed)
    reject.append(
        {
            "name": name,
            "note": note,
            "expect": expect,
            "streamExpect": expect if stream_expect is None else stream_expect,
            "bytes": len(compressed),
            "referenceRejects": reference_rejects,
        }
    )


# ==========================================================================
# Frame header guards.
# ==========================================================================
emit_reject(
    "guard-window-log",
    struct.pack("<I", MAGIC) + bytes([0x00, 0xF8]) + block(True, RAW, 1, b"x"),
    "window descriptor exponent 31 means a 41 bit window log",
    "impossible window log 41",
)

emit_reject(
    "guard-content-size-63bit",
    struct.pack("<I", MAGIC) + bytes([0xE0]) + b"\xff" * 8 + block(True, RAW, 1, b"x"),
    "eight byte content size with the top bit set",
    "does not fit a 63 bit integer",
)

emit_reject(
    "guard-dictionary-id",
    frame(
        [block(True, RAW, 1, b"x")],
        window_log=10,
        dictionary_id=0x2A,
        dictionary_width=1,
    ),
    "frame names dictionary 42, which Flucord cannot load",
    "Dictionary 42 is not supported",
)

emit_reject(
    "guard-dictionary-id-wide",
    frame(
        [block(True, RAW, 1, b"x")],
        window_log=10,
        dictionary_id=0x01020304,
        dictionary_width=4,
    ),
    "four byte dictionary id",
    "Dictionary 16909060 is not supported",
)

emit_reject(
    "guard-frame-header-cut",
    struct.pack("<I", MAGIC) + bytes([0xE0]) + b"\x00\x00\x00",
    "single segment frame promises eight content size bytes, sends three",
    "Frame header is truncated",
    stream_expect="undecodable bytes",
)

# ==========================================================================
# Frame level guards.
# ==========================================================================
emit_reject(
    "guard-skippable-header",
    struct.pack("<I", 0x184D2A50) + b"\x00\x00",
    "skippable frame stops inside its size field",
    "Skippable frame header is truncated",
    stream_expect="undecodable bytes",
)

emit_reject(
    "guard-skippable-overrun",
    struct.pack("<I", 0x184D2A5F) + struct.pack("<I", 0xFFFF),
    "skippable frame claims 65535 bytes of payload and sends none",
    "Skippable frame runs past the buffer",
    stream_expect="Stream ended inside a skippable frame",
)

emit_reject(
    "guard-block-header-cut",
    header(window_log=10) + b"\x00\x00",
    "frame header is complete, block header is two bytes short",
    "Block header is truncated",
    stream_expect="Stream ended inside a frame",
)

emit_reject(
    "guard-block-oversize",
    header(window_log=10) + block(True, RAW, MAX_BLOCK + 1),
    "block declares one byte more than the format maximum",
    "over the format maximum",
)

emit_reject(
    "guard-content-size-mismatch",
    frame(
        [block(True, RAW, 10, b"0123456789")],
        single_segment=True,
        content_size=100,
    ),
    "frame promises 100 bytes and emits 10",
    "declared 100 bytes but produced 10",
)

emit_reject(
    "guard-checksum-cut",
    frame(
        [block(True, RAW, 4, b"abcd")],
        single_segment=True,
        content_size=4,
        checksum=True,
    )
    + b"\x00\x00",
    "checksum flag set, only two of the four bytes sent",
    "Content checksum is truncated",
    stream_expect="Stream ended inside a frame",
)

# ==========================================================================
# Literals section guards.
# ==========================================================================
# libzstd 1.5.7 decodes this to nothing instead of failing, so it is the one
# fixture here where Flucord is deliberately stricter than the reference: a
# compressed block has no grammar without its Literals_Section_Header, and a
# peer that sends one is sending three bytes of nothing.
emit_reject(
    "guard-literals-missing",
    compressed_frame(b""),
    "compressed block with an empty body, which libzstd tolerates",
    "Compressed block has no literals section",
)

emit_reject(
    "guard-literals-past-block",
    compressed_frame(bytes([20 << 3]) + b"ab"),
    "raw literals claim 20 bytes inside a three byte block",
    "Literals section runs past the end of its block",
)

emit_reject(
    "guard-literals-oversize-raw",
    compressed_frame(literals_rle_wide(0x5A, 200000)[:3]),
    "RLE literals claim 200000 regenerated bytes",
    "Literals section claims 200000 bytes",
)

emit_reject(
    "guard-literals-oversize-huff",
    compressed_frame(literals_head(2, 3, 200000, 4) + b"\x00" * 4),
    "Huffman literals claim 200000 regenerated bytes",
    "Literals section claims 200000 bytes",
)

emit_reject(
    "guard-literals-treeless",
    compressed_frame(literals_head(3, 0, 4, 2) + b"\x00\x01"),
    "treeless literals in the first block of a frame",
    "Treeless literals arrived before any Huffman tree",
)

# ==========================================================================
# Huffman tree description guards.
# ==========================================================================
def huffman_block(section, regenerated=1, size_format=0):
    return literals_head(2, size_format, regenerated, len(section)) + section


emit_reject(
    "guard-huffman-missing",
    compressed_frame(huffman_block(b"")),
    "Huffman literals section is zero bytes long",
    "Huffman tree description is missing",
)

emit_reject(
    "guard-huffman-weights-cut",
    compressed_frame(huffman_block(bytes([0xFF]))),
    "direct weights promise 128 symbols, section holds one byte",
    "Huffman weights are truncated",
)

emit_reject(
    "guard-huffman-bitstream-cut",
    compressed_frame(huffman_block(bytes([0x05, 0x00]))),
    "weight bitstream promises five bytes, section holds one",
    "Huffman weight bitstream is truncated",
)

emit_reject(
    "guard-huffman-weight-range",
    compressed_frame(huffman_block(bytes([0x81, 0xF0]))),
    "direct weight nibble 15 is above the twelve bit code ceiling",
    "Huffman weight 15 is out of range",
)

emit_reject(
    "guard-huffman-no-codes",
    compressed_frame(huffman_block(bytes([0x81, 0x00]))),
    "every direct weight is zero",
    "Huffman tree assigns no codes",
)

emit_reject(
    "guard-huffman-code-length",
    compressed_frame(huffman_block(bytes([0x81, 0xCC]))),
    "two weights of twelve need a thirteen bit code",
    "Huffman code length 13 exceeds 12",
)

emit_reject(
    "guard-huffman-incomplete-tree",
    compressed_frame(huffman_block(bytes([0x81, 0x31]))),
    "weights 3 and 1 leave three slots, which is not a power of two",
    "Huffman weights do not complete the tree",
)

# One FSE weight table whose every transition reads zero bits, so the weight
# loop never runs the bitstream dry and only the 255 weight ceiling stops it.
_stuck = fse_count_header([32], 5) + reverse_stream([0] * 10)
emit_reject(
    "guard-huffman-many-weights",
    compressed_frame(huffman_block(bytes([len(_stuck)]) + _stuck)),
    "single symbol weight table never advances, so weights never end",
    "describes more than 255 weights",
)

# The same idea with a two symbol table: every transition costs exactly one bit,
# so the bitstream length decides when decoding stops. 254 update bits leaves
# the loop breaking on the 256th weight, one past what a tree may hold.
_overrun = fse_count_header([16, 16], 5) + reverse_stream([0] * 264)
emit_reject(
    "guard-huffman-weight-count",
    compressed_frame(huffman_block(bytes([len(_overrun)]) + _overrun)),
    "weight bitstream ends one weight past the 255 symbol ceiling",
    "Huffman tree has 256 weights",
)

_tree = bytes([0x81, 0x11])
emit_reject(
    "guard-huffman-jump-cut",
    compressed_frame(huffman_block(_tree + b"\x00\x00\x00", 4, size_format=1)),
    "four stream literals with a three byte jump table",
    "Huffman jump table is truncated",
)

emit_reject(
    "guard-huffman-jump-overrun",
    compressed_frame(huffman_block(_tree + b"\xff" * 6, 4, size_format=1)),
    "jump table sizes reach past the end of the literals section",
    "Huffman jump table overruns the literals section",
)

emit_reject(
    "guard-huffman-stream-count",
    compressed_frame(
        huffman_block(
            _tree + struct.pack("<HHH", 1, 1, 1) + b"\x01\x01\x01\x01",
            1,
            size_format=1,
        )
    ),
    "four streams cannot split a single literal",
    "Huffman streams cannot cover 1 literals",
)

# ==========================================================================
# FSE header guards.
# ==========================================================================
LITERAL_FSE_MODES = 2 << 6
OFFSET_FSE_MODES = 2 << 4

emit_reject(
    "guard-fse-accuracy-log",
    compressed_frame(literals_raw(b"") + sequence_section(1, LITERAL_FSE_MODES, b"\x05")),
    "literal length table asks for an eleven bit accuracy log",
    "FSE accuracy log 10 exceeds 9",
)

emit_reject(
    "guard-fse-skip-inner",
    compressed_frame(
        literals_raw(b"")
        + sequence_section(1, OFFSET_FSE_MODES, bytes([0x10, 0xFE, 0xFF, 0xFF]))
    ),
    "zero run of eleven groups skips past offset code 31",
    "Offset FSE header skips past symbol 31",
)

emit_reject(
    "guard-fse-skip-outer",
    compressed_frame(
        literals_raw(b"")
        + sequence_section(1, OFFSET_FSE_MODES, bytes([0x10, 0xFE, 0xFF, 0x5F]))
    ),
    "zero run lands two symbols past offset code 31",
    "Offset FSE header skips past symbol 31",
)

emit_reject(
    "guard-fse-incomplete",
    compressed_frame(huffman_block(bytes([0x02, 0x00, 0x00]), 4)),
    "all zero weight header leaves twenty probability points unassigned",
    "Huffman weight FSE distribution is incomplete",
)

emit_reject(
    "guard-fse-overrun",
    compressed_frame(
        literals_raw(b"") + sequence_section(1, OFFSET_FSE_MODES, b"\x00\x00")
    ),
    "offset distribution needs 21 header bytes and the block holds two",
    "Offset FSE header runs past the section",
)

# ==========================================================================
# Sequence section guards.
# ==========================================================================
emit_reject(
    "guard-sequences-missing",
    compressed_frame(literals_raw(b"abc")),
    "literals fill the block, leaving no sequence section",
    "Compressed block has no sequence section",
)

emit_reject(
    "guard-sequence-count-cut-long",
    compressed_frame(literals_raw(b"") + b"\xff\x00"),
    "long sequence count stops one byte short",
    "Sequence count is truncated",
)

emit_reject(
    "guard-sequence-count-cut-mid",
    compressed_frame(literals_raw(b"") + b"\x80"),
    "two byte sequence count stops after its first byte",
    "Sequence count is truncated",
)

emit_reject(
    "guard-sequence-modes-missing",
    compressed_frame(literals_raw(b"") + b"\xff\x00\x00"),
    "32512 sequences announced, no compression modes byte",
    "Sequence section has no compression modes",
)

emit_reject(
    "guard-sequence-empty-trailing",
    compressed_frame(literals_raw(b"") + b"\x00\xaa"),
    "zero sequence section followed by a stray byte",
    "Empty sequence section has trailing bytes",
)

emit_reject(
    "guard-sequence-modes-reserved",
    compressed_frame(literals_raw(b"") + b"\x01\x03"),
    "compression modes byte sets the two reserved bits",
    "Sequence modes set the reserved bits",
)

emit_reject(
    "guard-sequence-rle-missing",
    compressed_frame(literals_raw(b"") + b"\x01\x40"),
    "literal length table is RLE with no symbol byte behind it",
    "Literals length RLE symbol is missing",
)

emit_reject(
    "guard-sequence-rle-range",
    compressed_frame(literals_raw(b"") + b"\x01\x40\x24"),
    "literal length RLE symbol 36 is past the last legal code",
    "Literals length RLE symbol 36 is out of range",
)

emit_reject(
    "guard-sequence-repeat-table",
    compressed_frame(literals_raw(b"") + b"\x01\xc0"),
    "literal length table repeats before any table was sent",
    "Literals length table repeats but no table was ever sent",
)

emit_reject(
    "guard-sequence-bitstream-empty",
    compressed_frame(literals_raw(b"") + b"\x01\x00"),
    "predefined tables with a zero byte sequence bitstream",
    "Entropy bitstream is empty",
)

emit_reject(
    "guard-sequence-no-marker",
    compressed_frame(literals_raw(b"") + b"\x01\x00\x00"),
    "sequence bitstream ends on a zero byte, so it has no padding marker",
    "Entropy bitstream has no padding marker",
)

emit_reject(
    "guard-sequence-bitstream-short",
    compressed_frame(literals_raw(b"") + b"\x01\x00\x01"),
    "sequence bitstream holds only its padding marker",
    "Sequence 0 read past the end of its bitstream",
)

emit_reject(
    "guard-sequence-literals-short",
    compressed_frame(
        literals_raw(b"") + rle_sequences(1, 20, 0, 0, bit_list((0, 2)))
    ),
    "sequence wants 24 literals from a block that carries none",
    "Sequence 0 wants more literals than the block holds",
)

emit_reject(
    "guard-repeat-offset-underflow",
    compressed_frame(
        literals_raw(b"") + rle_sequences(1, 0, 1, 0, bit_list((1, 1))),
        before=[seed_block(b"12345678")],
    ),
    "offset code 3 with no literals steps the first repeat offset below one",
    "Repeat offset stepped below one",
)

emit_reject(
    "guard-match-offset-window",
    compressed_frame(
        literals_raw(b"") + rle_sequences(1, 0, 11, 0, bit_list((0, 11))),
        before=[seed_block(b"12345678")],
    ),
    "match reaches 2045 bytes back through a 1 KiB window",
    "Match offset 2045 exceeds the 1024 byte window",
)

# A match long enough to push one block past the 128 KiB regeneration ceiling.
emit_reject(
    "guard-block-regen-match",
    compressed_frame(
        literals_raw(b"") + rle_sequences(1, 0, 2, 52, bit_list((0, 2), (0xFFFF, 16))),
        before=[seed_block(b"x")],
    ),
    "one 131074 byte match regenerates more than a block may hold",
    "Block regenerates more than 131072 bytes",
)

# The sequences stay inside the ceiling; the literals left over at the end of
# the block are what pushes the total past it.
emit_reject(
    "guard-block-regen-literals",
    compressed_frame(
        literals_rle_wide(0x5A, 131060)
        + rle_sequences(1, 0, 2, 17, bit_list((0, 2))),
        before=[seed_block(b"x")],
    ),
    "trailing literals push a legal looking block past 128 KiB",
    "Block regenerates more than 131072 bytes",
)

# ==========================================================================
# Legal frames that reach paths libzstd never emits for the other corpora.
# ==========================================================================
emit_positive(
    "guard-rle-literals-wide",
    b"\x5a" * 5000,
    compressed_frame(literals_rle_wide(0x5A, 5000) + b"\x00", window_log=13),
    "RLE literals with a three byte header and no sequences",
)


def replay_repeat_offsets(seed, count, length=3):
    """Mirrors the repeat offset rules for Offset_Value 1 with no literals.

    Written out rather than taken from the reference decoder so the fixture is
    an assertion about the format, not a recording of whatever libzstd did.
    """
    out = bytearray(seed)
    first, second = 1, 4
    for _ in range(count):
        offset = second
        second, first = first, offset
        source = len(out) - offset
        for index in range(length):
            out.append(out[source + index])
    return bytes(out)


# 0x7f00 sequences is the smallest count that needs the three byte spelling.
# Offset code 0 with no literals means "the second repeat offset", so every
# sequence is decodable without reading a single bit of the bitstream.
_seed = b"flucord!"
_long_count = 0x7F00
emit_positive(
    "guard-long-sequence-count",
    replay_repeat_offsets(_seed, _long_count),
    compressed_frame(
        literals_raw(b"") + rle_sequences(_long_count, 0, 0, 0, []),
        before=[seed_block(_seed)],
        window_log=17,
    ),
    "32512 sequences, the smallest count using the long spelling",
)

emit_positive(
    "guard-repeat-offset-step",
    b"12345678" + b"123" + b"567",
    compressed_frame(
        literals_raw(b"") + rle_sequences(2, 0, 1, 0, bit_list((0, 1), (1, 1))),
        before=[seed_block(b"12345678")],
    ),
    "offset code 3 with no literals means one byte closer than the last match",
)

# libzstd only writes the direct weight spelling when the literal alphabet is
# small enough that FSE coding the weights would not pay, and only reaches the
# five byte literals header past 16383 regenerated bytes. This input does both.
random.seed(0x5EED)
_wide = bytes(random.randrange(16) for _ in range(17000))
emit_positive(
    "guard-huffman-direct-weights",
    _wide,
    zstandard.ZstdCompressor(level=1, write_content_size=False).compress(_wide),
    "direct Huffman weights behind a five byte literals header",
)

# A checksummed frame whose blocks are not multiples of 32 bytes, so the hash
# has to carry a partial buffer between blocks and fold a tail at the end.
_chunks = [bytes([0x40 + index]) * 47 for index in range(3)]
_compressor = zstandard.ZstdCompressor(
    level=1, write_checksum=True, write_content_size=False
).compressobj()
_parts = [
    _compressor.compress(chunk) + _compressor.flush(zstandard.COMPRESSOBJ_FLUSH_BLOCK)
    for chunk in _chunks
]
emit_positive(
    "guard-checksum-tail",
    b"".join(_chunks),
    b"".join(_parts) + _compressor.flush(zstandard.COMPRESSOBJ_FLUSH_FINISH),
    "checksum over blocks that are not multiples of 32 bytes",
)

json.dump(
    positive, open(os.path.join(OUT, "manifest-guard.json"), "w"), indent=2
)
json.dump(
    reject, open(os.path.join(OUT, "manifest-guard-reject.json"), "w"), indent=2
)

# The privacy audit reads manifests as text, and a digest that happens to hold
# a long run of decimal digits looks exactly like a Discord snowflake.
import re  # noqa: E402

for entry in positive:
    assert not re.search(
        r"(?<![0-9A-Fa-f])[0-9]{17,20}(?![0-9A-Fa-f])", entry["rawSha256"]
    ), "%s: digest looks like a snowflake, change the fixture" % entry["name"]

_kept = [entry for entry in reject if entry["referenceRejects"]]
print(
    "positive=%d reject=%d reference-rejects=%d bytes=%d"
    % (
        len(positive),
        len(reject),
        len(_kept),
        sum(e["compressedBytes"] for e in positive) + sum(e["bytes"] for e in reject),
    )
)
for entry in reject:
    if not entry["referenceRejects"]:
        print("  reference ACCEPTS %s — check that Flucord is right" % entry["name"])
