import 'dart:typed_data';

import 'package:flucord/src/presentation/expression_file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> prefix, int length) {
  final bytes = Uint8List(length);
  bytes.setAll(0, prefix);
  for (var index = prefix.length; index < length; index++) {
    bytes[index] = index % 256;
  }
  return bytes;
}

void main() {
  test('an emoji image is encoded to the data URI the route takes', () {
    final selection = ExpressionFileCodec.encode(
      ExpressionKind.emoji,
      'spark.png',
      _bytes(const [0x89, 0x50, 0x4e, 0x47], 32),
    );

    expect(selection.dataUri, startsWith('data:image/png;base64,'));
    expect(selection.byteCount, 32);
  });

  test('an animated emoji keeps its GIF type', () {
    final selection = ExpressionFileCodec.encode(
      ExpressionKind.emoji,
      'spark.gif',
      _bytes(const [0x47, 0x49, 0x46, 0x38], 32),
    );

    expect(selection.dataUri, startsWith('data:image/gif;base64,'));
  });

  test('an emoji over the limit is refused before anything is sent', () {
    final bytes = _bytes(const [
      0x89,
      0x50,
      0x4e,
      0x47,
    ], ExpressionFileCodec.emojiMaxBytes + 1);

    expect(
      () => ExpressionFileCodec.encode(ExpressionKind.emoji, 'big.png', bytes),
      throwsA(
        isA<ExpressionFileRejected>().having(
          (error) => error.message,
          'message',
          'Emoji images must be under 256 KB.',
        ),
      ),
    );
  });

  test('a sound over the limit is refused with its own sentence', () {
    final bytes = _bytes(const [
      0x49,
      0x44,
      0x33,
    ], ExpressionFileCodec.soundMaxBytes + 1);

    expect(
      () => ExpressionFileCodec.encode(ExpressionKind.sound, 'big.mp3', bytes),
      throwsA(
        isA<ExpressionFileRejected>().having(
          (error) => error.message,
          'message',
          'Sounds must be under 512 KB.',
        ),
      ),
    );
  });

  test('a sound file is read from its bytes, not its name', () {
    // An OGG file renamed to .mp3 is still declared audio/ogg, because the
    // server stores what the bytes are.
    final selection = ExpressionFileCodec.encode(
      ExpressionKind.sound,
      'renamed.mp3',
      _bytes(const [0x4f, 0x67, 0x67, 0x53], 32),
    );

    expect(selection.dataUri, startsWith('data:audio/ogg;base64,'));
  });

  test('the sticker format constraints are enforced per format', () {
    // PNG, GIF and Lottie JSON are sticker formats; JPEG and WebP are not.
    expect(
      ExpressionFileCodec.detectMediaType(
        ExpressionKind.sticker,
        _bytes(const [0x89, 0x50, 0x4e, 0x47], 32),
      ),
      'image/png',
    );
    expect(
      ExpressionFileCodec.detectMediaType(
        ExpressionKind.sticker,
        _bytes(const [0x47, 0x49, 0x46, 0x38], 32),
      ),
      'image/gif',
    );
    expect(
      ExpressionFileCodec.detectMediaType(
        ExpressionKind.sticker,
        Uint8List.fromList(utf8Json()),
      ),
      'application/json',
    );
    expect(
      ExpressionFileCodec.detectMediaType(
        ExpressionKind.sticker,
        _bytes(const [0xff, 0xd8, 0xff], 32),
      ),
      isNull,
    );
    expect(
      ExpressionFileCodec.detectMediaType(ExpressionKind.sticker, _webpBytes()),
      isNull,
    );
  });

  test('a sticker over the limit is refused with its own sentence', () {
    final bytes = _bytes(const [
      0x89,
      0x50,
      0x4e,
      0x47,
    ], ExpressionFileCodec.stickerMaxBytes + 1);

    expect(
      () =>
          ExpressionFileCodec.encode(ExpressionKind.sticker, 'big.png', bytes),
      throwsA(
        isA<ExpressionFileRejected>().having(
          (error) => error.message,
          'message',
          'Stickers must be under 512 KB, and 5 seconds at most.',
        ),
      ),
    );
  });

  test('a file of the wrong kind is refused plainly', () {
    expect(
      () => ExpressionFileCodec.encode(
        ExpressionKind.sound,
        'picture.mp3',
        _bytes(const [0x89, 0x50, 0x4e, 0x47], 32),
      ),
      throwsA(
        isA<ExpressionFileRejected>().having(
          (error) => error.message,
          'message',
          'Sounds must be an MP3 or OGG file.',
        ),
      ),
    );
  });

  test('an empty file is refused', () {
    expect(
      () => ExpressionFileCodec.encode(
        ExpressionKind.emoji,
        'empty.png',
        Uint8List(0),
      ),
      throwsA(
        isA<ExpressionFileRejected>().having(
          (error) => error.message,
          'message',
          'That file is empty.',
        ),
      ),
    );
  });
}

List<int> utf8Json() => const [0x7b, 0x22, 0x76, 0x22, 0x3a, 0x31, 0x7d];

Uint8List _webpBytes() {
  final bytes = Uint8List(16);
  bytes.setAll(0, const [0x52, 0x49, 0x46, 0x46]);
  bytes.setAll(8, const [0x57, 0x45, 0x42, 0x50]);
  return bytes;
}
