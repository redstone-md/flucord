import 'dart:typed_data';

import 'package:flucord/src/data/zstd/zstd_bit_reader.dart';
import 'package:flucord/src/data/zstd/zstd_block_decoder.dart';
import 'package:flucord/src/data/zstd/zstd_codec.dart';
import 'package:flucord/src/data/zstd/zstd_error.dart';
import 'package:flucord/src/data/zstd/zstd_fse.dart';
import 'package:flucord/src/data/zstd/zstd_sequences.dart';
import 'package:flucord/src/data/zstd/zstd_window.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards that no frame can reach, exercised through the classes that hold them.
///
/// `test/zstd_guard_test.dart` builds a frame for every check a hostile peer can
/// trip. The checks here sit behind an invariant an earlier check already
/// enforced — a match offset is positive because the offset codes make it so, a
/// literal run is inside its block because the sequence loop measured it — so
/// the only way to run them is to call the class directly. They are worth
/// keeping: each one turns a would-be `RangeError` into the [ZstdException] the
/// Gateway transport knows how to recover from, and each one is one refactor
/// away from being reachable.
///
/// Three checks are not testable even this way, because no public API can build
/// the state they watch for, and forcing them would mean weakening the checks
/// that come before:
///
/// * "FSE distribution overflows its table" — the header loop keeps
///   `threshold <= remaining < 2 * threshold`, which caps every decoded
///   probability at `remaining`, so the running total cannot go negative.
/// * "FSE state escaped a table" — for a table from `fromCounts`, a symbol
///   occupies exactly as many states as its count, so `newStates + 2^bits - 1`
///   is always one less than the table size.
/// * "Huffman table overflows"/"leaves slots partly unassigned" — the implied
///   final weight is chosen to make the code lengths sum to exactly the table
///   size, and no earlier weight can exceed the length that sum implies.
///
/// Ported models of all three were fuzzed with 900k FSE headers and 600k weight
/// sets while writing these tests; every other outcome of those functions
/// appeared and none of the three did.
void main() {
  Matcher failsWith(String expected) => throwsA(
    isA<ZstdException>().having(
      (error) => error.toString(),
      'message',
      contains(expected),
    ),
  );

  group('ZstdWindow', () {
    test('reports how much output is waiting to be drained', () {
      final window = ZstdWindow(windowSize: 1024);

      window.writeRun(0x41, 10);

      expect(window.pendingLength, 10);
      expect(window.produced, 10);
      expect(window.takeOutput().length, 10);
      expect(window.pendingLength, 0);
    });

    test('rejects a literal run that is not inside its source', () {
      final window = ZstdWindow(windowSize: 1024);
      final literals = Uint8List.fromList([1, 2, 3]);

      expect(
        () => window.writeBytes(literals, 2, 4),
        failsWith('Literal run of 4 bytes is not in the block'),
      );
      expect(
        () => window.writeBytes(literals, -1, 2),
        failsWith('Literal run of 2 bytes is not in the block'),
      );
    });

    test('rejects a match offset that is not positive', () {
      final window = ZstdWindow(windowSize: 1024)..writeRun(0x41, 8);

      expect(
        () => window.copyMatch(0, 4),
        failsWith('Match offset 0 is not positive'),
      );
    });

    test('rejects a match longer than two blocks', () {
      final window = ZstdWindow(windowSize: 1 << 20)..writeRun(0x41, 8);

      expect(
        () => window.copyMatch(4, 1 << 19),
        failsWith('Match length 524288 is out of range'),
      );
    });
  });

  group('ZstdFseTable', () {
    test('rejects a distribution that does not fill the table', () {
      expect(
        () => ZstdFseTable.fromCounts([1, 2], 1, 5),
        failsWith('FSE distribution sums to 3, expected 32'),
      );
    });

    test('rejects a distribution whose spread does not close its cycle', () {
      // The counts add up to the table size, so the sum check passes, but a
      // negative count contributes nothing to the spread walk and leaves it
      // two steps away from where it started.
      expect(
        () => ZstdFseTable.fromCounts([-2, 34], 1, 5),
        failsWith('FSE table spread did not close its cycle'),
      );
    });
  });

  group('bit readers', () {
    test('a reverse reader reports the bits it has left', () {
      // The marker byte's highest set bit is padding, so a two byte stream
      // whose last byte is 0x04 carries ten bits of payload.
      final reader = ZstdReverseBitReader(
        Uint8List.fromList([0xFF, 0x04]),
        0,
        2,
      );

      expect(reader.bitsLeft, 10);
      expect(reader.isOverrun, isFalse);
      reader.skipBits(11);
      expect(reader.bitsLeft, -1);
      expect(reader.isOverrun, isTrue);
      expect(
        () => reader.requireInBounds('Huffman literals'),
        failsWith('Huffman literals read past the end of its bitstream'),
      );
    });

    test('a forward reader rejects a region that runs backwards', () {
      expect(
        () => ZstdForwardBitReader(Uint8List(8), 5, 2),
        failsWith('Entropy header is out of bounds'),
      );
      expect(
        () => ZstdForwardBitReader(Uint8List(8), -1, 2),
        failsWith('Entropy header is out of bounds'),
      );
    });
  });

  test('the highest bit of a non-positive value has no answer', () {
    expect(() => zstdHighestBit(0), failsWith('asked for the log of 0'));
  });

  test('a sequence code outside its table is refused, not indexed', () {
    // Every table the block reader installs is built against the code limit,
    // so a frame cannot carry a code this large. A carried-over table can:
    // the three fields are plain mutable state, and Repeat mode hands whatever
    // is in them straight to the sequence loop, which indexes the baseline
    // tables with the decoded code.
    final state = ZstdSequenceState()
      ..literalLengths = ZstdFseTable.rle(200)
      ..offsets = ZstdFseTable.rle(0)
      ..matchLengths = ZstdFseTable.rle(0);

    expect(
      () => executeZstdSequences(
        // One sequence, all three tables in Repeat mode, one marker byte.
        block: Uint8List.fromList([0x01, 0xFC, 0x01]),
        start: 0,
        end: 3,
        literals: Uint8List(0),
        state: state,
        window: ZstdWindow(windowSize: 1024),
      ),
      failsWith('Sequence 0 decoded an out of range code'),
    );
  });

  test('an RLE block body is exactly one byte', () {
    // Both frame readers pass a one byte body by construction, so this only
    // fires if a third caller ever passes the block header's regenerated size
    // through as a body length.
    final decoder = ZstdBlockDecoder()..startFrame();

    expect(
      () => decoder.decodeBlock(
        type: ZstdBlockType.rle,
        regenerated: 4,
        bytes: Uint8List.fromList([1, 2, 3]),
        start: 0,
        end: 2,
        window: ZstdWindow(windowSize: 1024),
      ),
      failsWith('RLE block carries 2 bytes'),
    );
  });
}
