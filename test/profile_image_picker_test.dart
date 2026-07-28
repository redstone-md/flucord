import 'dart:convert';
import 'dart:typed_data';

import 'package:flucord/src/presentation/profile_image_picker.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> prefix, {int pad = 8}) =>
    Uint8List.fromList([...prefix, ...List.filled(pad, 0)]);

void main() {
  group('media type', () {
    test('reads the format from the bytes, not the name', () {
      expect(
        ProfileImageCodec.detectMediaType(
          _bytes(const [0x89, 0x50, 0x4e, 0x47]),
        ),
        'image/png',
      );
      expect(
        ProfileImageCodec.detectMediaType(_bytes(const [0xff, 0xd8, 0xff])),
        'image/jpeg',
      );
      expect(
        ProfileImageCodec.detectMediaType(
          _bytes(const [0x47, 0x49, 0x46, 0x38]),
        ),
        'image/gif',
      );
      expect(
        ProfileImageCodec.detectMediaType(
          Uint8List.fromList([
            0x52, 0x49, 0x46, 0x46, // RIFF
            0x10, 0x00, 0x00, 0x00, // size, ignored
            0x57, 0x45, 0x42, 0x50, // WEBP
          ]),
        ),
        'image/webp',
      );
    });

    test('a RIFF container that is not WebP is not an image Discord takes', () {
      final wave = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46,
        0x10, 0x00, 0x00, 0x00,
        0x57, 0x41, 0x56, 0x45, // WAVE
      ]);
      expect(ProfileImageCodec.detectMediaType(wave), isNull);
    });

    test('a truncated RIFF header does not read past the end', () {
      final short = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0x00]);
      expect(ProfileImageCodec.detectMediaType(short), isNull);
    });

    test('a file shorter than any signature is rejected, not indexed', () {
      expect(
        ProfileImageCodec.detectMediaType(Uint8List.fromList([0x89])),
        isNull,
      );
    });

    test('an unknown format is rejected', () {
      expect(
        ProfileImageCodec.detectMediaType(_bytes(const [0x00, 0x01])),
        isNull,
      );
    });
  });

  group('encode', () {
    test('produces the data URI the profile route accepts', () {
      final png = _bytes(const [0x89, 0x50, 0x4e, 0x47]);

      final selection = ProfileImageCodec.encode('avatar.png', png);

      expect(selection.name, 'avatar.png');
      expect(selection.byteCount, png.length);
      expect(selection.dataUri, 'data:image/png;base64,${base64Encode(png)}');
    });

    test('an empty file is refused', () {
      expect(
        () => ProfileImageCodec.encode('empty.png', Uint8List(0)),
        throwsA(
          isA<ProfileImageRejected>().having(
            (error) => error.reason,
            'reason',
            ProfileImageRejection.empty,
          ),
        ),
      );
    });

    test('a file over the limit is refused before it is encoded', () {
      final huge = Uint8List(ProfileImageCodec.maxBytes + 1)
        ..setRange(0, 4, const [0x89, 0x50, 0x4e, 0x47]);

      expect(
        () => ProfileImageCodec.encode('huge.png', huge),
        throwsA(
          isA<ProfileImageRejected>().having(
            (error) => error.reason,
            'reason',
            ProfileImageRejection.tooLarge,
          ),
        ),
      );
    });

    test('a format Discord does not store is refused', () {
      expect(
        () => ProfileImageCodec.encode('doc.pdf', _bytes(const [0x25, 0x50])),
        throwsA(
          isA<ProfileImageRejected>().having(
            (error) => error.reason,
            'reason',
            ProfileImageRejection.unsupportedFormat,
          ),
        ),
      );
    });

    test('every rejection carries a message the form can show', () {
      for (final reason in ProfileImageRejection.values) {
        final rejected = ProfileImageRejected(reason);
        expect(rejected.message, isNotEmpty);
        expect(rejected.toString(), rejected.message);
      }
    });
  });
}
