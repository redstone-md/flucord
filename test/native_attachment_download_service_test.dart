import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/native_attachment_download_service.dart';
import 'package:flucord/src/domain/attachment_download.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test(
    'streams into a sibling part and replaces only after completion',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flucord-attachment-save-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final destination = File(
        '${directory.path}${Platform.pathSeparator}report.bin',
      );
      await destination.writeAsString('previous bytes');
      final body = Uint8List.fromList(
        List.generate(4096, (index) => index % 251),
      );
      final server = await _serve((request) async {
        request.response.contentLength = body.length;
        request.response.add(body.sublist(0, 1024));
        await request.response.flush();
        request.response.add(body.sublist(1024));
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      final picker = _FakeLocationPicker(destination.path);
      final service = NativeAttachmentDownloadService(
        locationPicker: picker,
        clock: () => DateTime.utc(2026, 7, 24, 3, 47),
      );
      final progress = <AttachmentDownloadProgress>[];

      final result = await service.save(
        _attachment(server, size: body.length),
        cancellation: AttachmentDownloadCancellation(),
        onProgress: progress.add,
      );

      expect(result?.path, destination.path);
      expect(result?.bytesWritten, body.length);
      expect(await destination.readAsBytes(), body);
      expect(progress.first.receivedBytes, 0);
      expect(progress.last.fraction, 1);
      expect(
        directory.listSync().where((entry) => entry.path.contains('.flucord-')),
        isEmpty,
      );
    },
  );

  test(
    'cancellation keeps an existing destination and removes the part',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flucord-attachment-cancel-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final destination = File(
        '${directory.path}${Platform.pathSeparator}report.bin',
      );
      await destination.writeAsString('keep me');
      final firstChunkWritten = Completer<void>();
      final server = await _serve((request) async {
        try {
          request.response.contentLength = 2048;
          request.response.add(List.filled(1024, 1));
          await request.response.flush();
          firstChunkWritten.complete();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          request.response.add(List.filled(1024, 2));
          await request.response.close();
        } on Object {
          if (!firstChunkWritten.isCompleted) firstChunkWritten.complete();
        }
      });
      addTearDown(() => server.close(force: true));
      final cancellation = AttachmentDownloadCancellation();
      final service = NativeAttachmentDownloadService(
        locationPicker: _FakeLocationPicker(destination.path),
      );

      final result = await service.save(
        _attachment(server, size: 2048),
        cancellation: cancellation,
        onProgress: (progress) {
          if (progress.receivedBytes > 0) cancellation.cancel();
        },
      );
      await firstChunkWritten.future;

      expect(result, isNull);
      expect(await destination.readAsString(), 'keep me');
      expect(
        directory.listSync().where((entry) => entry.path.contains('.flucord-')),
        isEmpty,
      );
    },
  );

  test('HTTP failure keeps the destination intact', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flucord-attachment-failure-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final destination = File(
      '${directory.path}${Platform.pathSeparator}report.bin',
    );
    await destination.writeAsString('stable');
    final server = await _serve((request) async {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final service = NativeAttachmentDownloadService(
      locationPicker: _FakeLocationPicker(destination.path),
    );

    await expectLater(
      service.save(
        _attachment(server),
        cancellation: AttachmentDownloadCancellation(),
        onProgress: (_) {},
      ),
      throwsA(isA<HttpException>()),
    );

    expect(await destination.readAsString(), 'stable');
  });

  test('rejects non-HTTP sources before opening the picker', () async {
    final picker = _FakeLocationPicker(r'C:\downloads\note.txt');
    final service = NativeAttachmentDownloadService(locationPicker: picker);

    await expectLater(
      service.save(
        const MessageAttachment(
          id: 'local',
          fileName: 'note.txt',
          url: 'file:///private/note.txt',
          size: 10,
        ),
        cancellation: AttachmentDownloadCancellation(),
        onProgress: (_) {},
      ),
      throwsArgumentError,
    );

    expect(picker.calls, 0);
  });

  test('picker cancellation does not open a network connection', () async {
    var clientsCreated = 0;
    final service = NativeAttachmentDownloadService(
      locationPicker: _FakeLocationPicker(null),
      httpClientFactory: () {
        clientsCreated++;
        return HttpClient();
      },
    );

    final result = await service.save(
      const MessageAttachment(
        id: 'cancelled',
        fileName: 'note.txt',
        url: 'https://cdn.discordapp.com/note.txt',
        size: 10,
      ),
      cancellation: AttachmentDownloadCancellation(),
      onProgress: (_) {},
    );

    expect(result, isNull);
    expect(clientsCreated, 0);
  });

  test('sanitizes server-controlled suggested file names', () {
    expect(
      NativeAttachmentSaveLocationPicker.sanitizeFileName(
        r'..\CON:<release>|?.zip ',
      ),
      '.._CON__release___.zip',
    );
    expect(
      NativeAttachmentSaveLocationPicker.sanitizeFileName('NUL.txt'),
      '_NUL.txt',
    );
  });
}

Future<HttpServer> _serve(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) => unawaited(handler(request)));
  return server;
}

MessageAttachment _attachment(HttpServer server, {int size = 32}) =>
    MessageAttachment(
      id: 'attachment-1',
      fileName: 'report.bin',
      url: 'http://${server.address.address}:${server.port}/report.bin',
      size: size,
      contentType: 'application/octet-stream',
    );

final class _FakeLocationPicker implements AttachmentSaveLocationPicker {
  _FakeLocationPicker(this.path);

  final String? path;
  int calls = 0;

  @override
  Future<String?> chooseDestination(String suggestedName) async {
    calls++;
    return path;
  }
}
