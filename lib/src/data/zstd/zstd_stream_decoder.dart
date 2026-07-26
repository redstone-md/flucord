import 'dart:typed_data';

import 'zstd_block_decoder.dart';
import 'zstd_error.dart';
import 'zstd_frame_decoder.dart';
import 'zstd_frame_header.dart';
import 'zstd_window.dart';
import 'zstd_xxh64.dart';

/// Incremental Zstandard decoder for one continuous stream.
///
/// Discord's Gateway negotiates `compress=zstd-stream`, which means a single
/// frame spans the whole connection and every WebSocket message carries an
/// arbitrary slice of it. Nothing guarantees that a message boundary lines up
/// with a frame header, a block header, or a block body, so the decoder has to
/// hold partial input and keep the match window alive between calls.
final class ZstdStreamDecoder {
  ZstdStreamDecoder({required this.maxWindowLog});

  final int maxWindowLog;

  final ZstdBlockDecoder _blocks = ZstdBlockDecoder();
  final ZstdXxh64 _checksum = ZstdXxh64();

  Uint8List _buffer = Uint8List(0);
  int _start = 0;
  int _end = 0;

  ZstdFrameHeader? _frame;
  ZstdWindow? _window;
  int _skipRemaining = 0;
  bool _awaitingChecksum = false;

  /// Feeds one chunk and returns everything that became decodable.
  Uint8List feed(List<int> chunk) {
    _append(chunk);
    final output = BytesBuilder(copy: false);
    while (_advance(output)) {}
    return output.takeBytes();
  }

  /// Asserts the stream ended on a frame boundary.
  ///
  /// Truncation is invisible while bytes are still arriving: a half-delivered
  /// block looks exactly like one that has not finished yet. Only the producer
  /// closing the stream turns that into an error, so callers have to say so.
  void finish() {
    if (_frame != null || _awaitingChecksum) {
      zstdFail('Stream ended inside a frame', _start);
    }
    if (_skipRemaining > 0) {
      zstdFail('Stream ended inside a skippable frame', _start);
    }
    if (_end > _start) {
      zstdFail('Stream ended with ${_end - _start} undecodable bytes', _start);
    }
  }

  /// Drops all buffered input and frame history.
  ///
  /// A reconnect starts a new stream with its own window; carrying history over
  /// would let matches resolve against the previous session's data.
  void reset() {
    _buffer = Uint8List(0);
    _start = 0;
    _end = 0;
    _frame = null;
    _window = null;
    _skipRemaining = 0;
    _awaitingChecksum = false;
  }

  int get _available => _end - _start;

  bool _advance(BytesBuilder output) {
    if (_skipRemaining > 0) return _skipBytes();
    if (_awaitingChecksum) return _readChecksum();
    if (_frame == null) return _readHeader();
    return _readBlock(output);
  }

  bool _skipBytes() {
    if (_available == 0) return false;
    final consumed = _skipRemaining < _available ? _skipRemaining : _available;
    _start += consumed;
    _skipRemaining -= consumed;
    return true;
  }

  bool _readHeader() {
    if (_available < 4) return false;
    final view = ByteData.sublistView(_buffer);
    final magic = view.getUint32(_start, Endian.little);

    if (magic >= zstdSkippableMagicLow && magic <= zstdSkippableMagicHigh) {
      if (_available < 8) return false;
      _skipRemaining = view.getUint32(_start + 4, Endian.little);
      _start += 8;
      return true;
    }
    if (magic != zstdFrameMagic) {
      zstdFail('Stream does not start with a Zstandard frame', _start);
    }

    final size = zstdFrameHeaderSize(_buffer, _start, _end);
    if (size == null || _start + size > _end) return false;

    final header = readZstdFrameHeader(
      _buffer,
      _start,
      _end,
      maxWindowLog: maxWindowLog,
    );
    _frame = header;
    _window = ZstdWindow(windowSize: header.windowSize);
    _blocks.startFrame();
    if (header.hasChecksum) _checksum.reset();
    _start += header.headerSize;
    return true;
  }

  bool _readBlock(BytesBuilder output) {
    if (_available < 3) return false;
    final descriptor =
        _buffer[_start] |
        (_buffer[_start + 1] << 8) |
        (_buffer[_start + 2] << 16);
    final size = descriptor >> 3;
    if (size > zstdBlockMaximumSize) {
      zstdFail('Block declares $size bytes, over the format maximum', _start);
    }
    final last = (descriptor & 1) != 0;
    final type = (descriptor >> 1) & 3;
    // An RLE block's header size is its regenerated length, not its body
    // length. Waiting for that many bytes would stall a live stream forever:
    // feed() would keep returning empty while the socket looked healthy.
    final bodySize = type == ZstdBlockType.rle ? 1 : size;
    if (_available < 3 + bodySize) return false;

    final body = _start + 3;
    final header = _frame!;
    final window = _window!;

    _blocks.decodeBlock(
      type: type,
      regenerated: size,
      bytes: _buffer,
      start: body,
      end: body + bodySize,
      window: window,
    );
    _start = body + bodySize;

    final produced = window.takeOutput();
    if (produced.isNotEmpty) {
      if (header.hasChecksum) _checksum.add(produced);
      output.add(produced);
    }

    if (!last) return true;

    final declared = header.contentSize;
    if (declared != null && declared != window.produced) {
      zstdFail(
        'Frame declared $declared bytes but produced ${window.produced}',
        _start,
      );
    }
    if (header.hasChecksum) {
      _awaitingChecksum = true;
    }
    _frame = null;
    _window = null;
    return true;
  }

  bool _readChecksum() {
    if (_available < 4) return false;
    final expected = ByteData.sublistView(
      _buffer,
    ).getUint32(_start, Endian.little);
    final actual = _checksum.digest & 0xffffffff;
    if (expected != actual) {
      zstdFail('Content checksum does not match the decoded data', _start);
    }
    _start += 4;
    _awaitingChecksum = false;
    return true;
  }

  void _append(List<int> chunk) {
    if (chunk.isEmpty) return;
    final retained = _end - _start;
    final needed = retained + chunk.length;
    if (needed > _buffer.length) {
      var capacity = _buffer.isEmpty ? 4096 : _buffer.length;
      while (capacity < needed) {
        capacity *= 2;
      }
      final grown = Uint8List(capacity);
      grown.setRange(0, retained, _buffer, _start);
      _buffer = grown;
    } else if (_start > 0) {
      _buffer.setRange(0, retained, _buffer, _start);
    }
    _start = 0;
    _end = retained;
    _buffer.setRange(_end, _end + chunk.length, chunk);
    _end += chunk.length;
  }
}
