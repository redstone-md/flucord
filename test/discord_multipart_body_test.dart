import 'dart:convert';
import 'dart:io';

import 'package:flucord/src/data/discord/discord_multipart_body.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The multipart form the sticker route sends. The shape on the wire is the
/// whole contract: a reader on Discord's side splits on the boundary, so
/// what these tests assert is what that reader would see.
void main() {
  group('buildForm', () {
    test('every field is its own part, in order', () async {
      final body = await DiscordMultipartBody.buildForm({
        'name': 'Aurora',
        'description': 'The server seal.',
        'tags': 'seal',
      }, []);

      final text = utf8.decode(body.bytes);
      expect(body.contentType, startsWith('multipart/form-data; boundary='));
      // The payload_json part is the message route's shape; a form route
      // carries plain fields and must not mix the two.
      expect(text, isNot(contains('payload_json')));
      expect(text, contains('name="name"\r\n\r\nAurora\r\n'));
      expect(text, contains('name="description"\r\n\r\nThe server seal.\r\n'));
      expect(text, contains('name="tags"\r\n\r\nseal\r\n'));
      // The closer ends the form and nothing follows it.
      expect(text.endsWith('\r\n'), isTrue);
      final boundary = body.contentType.split('boundary=').last;
      final closer = '--$boundary--\r\n';
      expect(text.indexOf(closer), text.length - closer.length);
    });

    test(
      'a form with no fields and no files is still a valid empty form',
      () async {
        final body = await DiscordMultipartBody.buildForm({}, []);

        final text = utf8.decode(body.bytes);
        final boundary = body.contentType.split('boundary=').last;
        // Only the closer is on the wire.
        expect(text, '--$boundary--\r\n');
        expect(body.bytes, utf8.encode(text));
      },
    );

    test('a filename that would break the header is sanitised', () async {
      final body = await DiscordMultipartBody.buildForm(const {}, [
        (
          name: 'file',
          filename: 'evil"quote\r\nInjected: yes\r\nB:new.png',
          bytes: [1, 2, 3],
        ),
      ]);

      final text = utf8.decode(body.bytes);
      // Quotes and line breaks become underscores, so the disposition stays
      // one header line and the injection never reaches the reader.
      expect(text, contains('filename="evil_quote__Injected: yes__B:new.png"'));
      expect(
        RegExp(r'filename="[^"]*[\r\n]').hasMatch(text),
        isFalse,
        reason: 'a filename must not carry a line break',
      );
    });

    test('a filename is trimmed of whitespace at the edges', () async {
      final body = await DiscordMultipartBody.buildForm(const {}, [
        (name: 'file', filename: '  seal.png  ', bytes: [1]),
      ]);

      final text = utf8.decode(body.bytes);
      expect(text, contains('filename="seal.png"'));
    });

    test('file bytes ride the part after the headers, verbatim', () async {
      final payload = List<int>.generate(256, (index) => index);
      final body = await DiscordMultipartBody.buildForm(const {}, [
        (name: 'file', filename: 'a.png', bytes: payload),
        (name: 'file', filename: 'b.gif', bytes: payload),
      ]);

      // Scanned as latin1, where every byte is one character: file bytes
      // are arbitrary and need not be valid UTF-8.
      final text = latin1.decode(body.bytes);
      final boundary = body.contentType.split('boundary=').last;
      // Two file parts, each named file, in the order the list carried.
      expect('name="file"; filename="a.png"'.allMatches(text), hasLength(1));
      expect('name="file"; filename="b.gif"'.allMatches(text), hasLength(1));
      // The content type names the file's kind from its extension.
      expect(text, contains('Content-Type: image/png\r\n\r\n'));
      expect(text, contains('Content-Type: image/gif\r\n\r\n'));
      // The bytes are exactly there, once, after each header.
      final firstPart = text.substring(text.indexOf('a.png'));
      final after = firstPart.substring(firstPart.indexOf('\r\n\r\n') + 4);
      final bytesOnWire = after.codeUnits.take(payload.length);
      expect(bytesOnWire, payload);
      expect(text, isNot(contains('--$boundary--\r\n--$boundary')));
    });

    test('a file part named for the boundary cannot split the form', () async {
      final body = await DiscordMultipartBody.buildForm(const {}, [
        (name: 'file', filename: 'x.png', bytes: [1]),
      ]);
      final boundary = body.contentType.split('boundary=').last;
      final hostile = await DiscordMultipartBody.buildForm(const {}, [
        // The filename carries the boundary this body was built with,
        // read back off its own content type.
        (
          name: 'file',
          filename: '--${body.contentType.split('boundary=').last}',
          bytes: [1, 2],
        ),
      ]);

      // The wire spells a frame as the dashes plus the boundary, and the
      // boundary already carries its own leading dashes.
      final frame = '--$boundary\r\n';
      final closer = '--$boundary--\r\n';
      final text = latin1.decode(hostile.bytes);
      final ownBoundary = hostile.contentType.split('boundary=').last;
      expect(
        text.contains('filename="--$boundary"'),
        isTrue,
        reason: 'the hostile filename reached the header intact',
      );
      // The body's own terminator closes it, exactly once, at the end.
      final ownCloser = '--$ownBoundary--\r\n';
      expect(text.indexOf(ownCloser), text.length - ownCloser.length);
      expect(frame.allMatches(text), hasLength(0));
      expect(closer.allMatches(text), hasLength(0));
    });
  });

  group('_contentTypeFor, through buildForm', () {
    Future<String> contentTypeOf(String filename) async {
      final body = await DiscordMultipartBody.buildForm(const {}, [
        (name: 'file', filename: filename, bytes: [1]),
      ]);
      final text = utf8.decode(body.bytes);
      final marker = 'Content-Type: ';
      final start = text.indexOf(marker) + marker.length;
      return text.substring(start, text.indexOf('\r\n', start));
    }

    test('the known extensions name their kinds', () async {
      expect(await contentTypeOf('a.png'), 'image/png');
      expect(await contentTypeOf('a.jpg'), 'image/jpeg');
      expect(await contentTypeOf('a.jpeg'), 'image/jpeg');
      expect(await contentTypeOf('a.gif'), 'image/gif');
      expect(await contentTypeOf('a.webp'), 'image/webp');
      expect(await contentTypeOf('a.txt'), 'text/plain');
      expect(await contentTypeOf('a.log'), 'text/plain');
      expect(await contentTypeOf('a.md'), 'text/plain');
      expect(await contentTypeOf('a.pdf'), 'application/pdf');
      expect(await contentTypeOf('a.ogg'), 'audio/ogg');
      expect(await contentTypeOf('a.opus'), 'audio/ogg');
    });

    test('an unknown extension is an octet stream', () async {
      expect(await contentTypeOf('a.apng'), 'application/octet-stream');
      expect(await contentTypeOf('a'), 'application/octet-stream');
    });

    test('the extension is read case-insensitively', () async {
      expect(await contentTypeOf('A.PNG'), 'image/png');
      expect(await contentTypeOf('A.Md'), 'text/plain');
    });
  });

  group('build, over a real file', () {
    late Directory temporary;
    late File file;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('flucord-multipart');
      file = File('${temporary.path}${Platform.pathSeparator}note.png')
        ..writeAsBytesSync([9, 8, 7]);
    });

    tearDown(() async => temporary.delete(recursive: true));

    test('the payload_json part leads and the file parts follow', () async {
      final body = await DiscordMultipartBody.build(
        const {'content': 'hello'},
        [PendingAttachment(name: 'note.png', path: file.path, size: 3)],
      );

      final text = latin1.decode(body.bytes);
      final boundary = body.contentType.split('boundary=').last;
      final firstFrame = text.indexOf('--$boundary');
      expect(
        text.indexOf('name="payload_json"'),
        firstFrame +
            '--$boundary\r\n'.length +
            'Content-Disposition: form-data; '.length,
        reason: 'the payload is the first part',
      );
      expect(text, contains('Content-Type: application/json\r\n\r\n'));
      expect(text, contains('"content":"hello"'));
      expect(text, contains('name="files[0]"; filename="note.png"'));
      expect(text, contains('Content-Type: image/png'));
      expect(text.codeUnits, containsAllInOrder([9, 8, 7]));
      // Only the closer ends the body.
      expect('--$boundary--\r\n'.allMatches(text), hasLength(1));
    });

    test(
      'an attachment header with a quote or break cannot split the part',
      () async {
        final body = await DiscordMultipartBody.build(const {}, [
          PendingAttachment(name: 'a"b\r\nc.png', path: file.path, size: 3),
        ]);

        final text = latin1.decode(body.bytes);
        expect(text, contains('filename="a_b__c.png"'));
        expect(
          RegExp(r'filename="[^"\r\n]*"').allMatches(text),
          everyElement(
            predicate(
              (match) => !(match as RegExpMatch).group(0)!.contains('\r\n'),
            ),
          ),
          reason: 'no filename header carries a line break',
        );
      },
    );
  });
}
