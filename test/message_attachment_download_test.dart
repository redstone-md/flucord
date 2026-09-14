import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/attachment_download.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/message_attachment_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('shows progress, supports cancel, and restores download', (
    tester,
  ) async {
    final service = _FakeDownloadService();
    await tester.pumpWidget(_attachmentApp(_fileAttachment, service));

    await tester.tap(find.byKey(const ValueKey('download-attachment-file-1')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('cancel-download-attachment-file-1')),
      findsOneWidget,
    );

    service.emit(
      const AttachmentDownloadProgress(receivedBytes: 50, totalBytes: 100),
    );
    await tester.pump();
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      0.5,
    );

    await tester.tap(
      find.byKey(const ValueKey('cancel-download-attachment-file-1')),
    );
    await tester.pump();
    expect(service.cancellations.single.isCancelled, isTrue);
    expect(
      find.byKey(const ValueKey('download-attachment-file-1')),
      findsOneWidget,
    );
    service.complete(null);
  });

  testWidgets('retains success and turns failure into retry', (tester) async {
    final service = _FakeDownloadService();
    await tester.pumpWidget(_attachmentApp(_fileAttachment, service));

    await tester.tap(find.byKey(const ValueKey('download-attachment-file-1')));
    await tester.pump();
    service.complete(
      const AttachmentDownloadResult(
        path: r'C:\Downloads\report.zip',
        bytesWritten: 100,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('save-again-attachment-file-1')),
      findsOneWidget,
    );
    expect(find.text('Saved report.zip'), findsOneWidget);

    service.failNext = true;
    await tester.tap(
      find.byKey(const ValueKey('save-again-attachment-file-1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('retry-download-attachment-file-1')),
      findsOneWidget,
    );
  });

  for (final attachment in _mediaAttachments) {
    testWidgets('exposes download for ${attachment.contentType}', (
      tester,
    ) async {
      await tester.pumpWidget(
        _attachmentApp(attachment, _FakeDownloadService()),
      );

      expect(
        find.byKey(ValueKey('download-attachment-${attachment.id}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keeps the media control inside compact attachment geometry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _attachmentApp(_videoAttachment, _FakeDownloadService()),
    );

    final attachmentRect = tester.getRect(
      find.byKey(const ValueKey('attachment-video-video-1')),
    );
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('download-attachment-video-1')),
    );
    expect(buttonRect.left, greaterThanOrEqualTo(attachmentRect.left));
    expect(buttonRect.right, lessThanOrEqualTo(attachmentRect.right));
    expect(buttonRect.top, greaterThanOrEqualTo(attachmentRect.top));
    expect(buttonRect.bottom, lessThanOrEqualTo(attachmentRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps audio download beside native playback controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 180));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _attachmentApp(_audioAttachment, _FakeDownloadService()),
    );

    final playerRect = tester.getRect(
      find.byKey(const ValueKey('attachment-audio-audio-1')),
    );
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('download-attachment-audio-1')),
    );
    expect(buttonRect.left, greaterThanOrEqualTo(playerRect.right));
    expect(buttonRect.right, lessThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
  });
}

Widget _attachmentApp(
  MessageAttachment attachment,
  AttachmentDownloadService service,
) => MaterialApp(
  theme: FlucordTheme.dark,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: MessageAttachmentView(
        attachment: attachment,
        downloadService: service,
        inlineVideoBuilder: ({required url, required aspectRatio, key}) =>
            SizedBox(key: key, width: 260, height: 140),
        inlineVoiceBuilder:
            ({required url, required duration, required waveform, key}) =>
                SizedBox(key: key, width: 260, height: 64),
      ),
    ),
  ),
);

const _fileAttachment = MessageAttachment(
  id: 'file-1',
  fileName: 'report.zip',
  url: 'https://cdn.discordapp.com/report.zip',
  size: 100,
  contentType: 'application/zip',
);

const _imageAttachment = MessageAttachment(
  id: 'image-1',
  fileName: 'capture.png',
  url: 'https://cdn.discordapp.com/capture.png',
  size: 100,
  contentType: 'image/png',
  width: 320,
  height: 180,
);

const _videoAttachment = MessageAttachment(
  id: 'video-1',
  fileName: 'capture.mp4',
  url: 'https://cdn.discordapp.com/capture.mp4',
  size: 100,
  contentType: 'video/mp4',
);

const _audioAttachment = MessageAttachment(
  id: 'audio-1',
  fileName: 'voice.ogg',
  url: 'https://cdn.discordapp.com/voice.ogg',
  size: 100,
  contentType: 'audio/ogg',
  durationSecs: 2,
);

const _mediaAttachments = [
  _imageAttachment,
  _videoAttachment,
  _audioAttachment,
];

final class _FakeDownloadService implements AttachmentDownloadService {
  final List<AttachmentDownloadCancellation> cancellations = [];
  Completer<AttachmentDownloadResult?>? _completion;
  AttachmentDownloadProgressCallback? _onProgress;
  bool failNext = false;

  @override
  Future<AttachmentDownloadResult?> save(
    MessageAttachment attachment, {
    required AttachmentDownloadCancellation cancellation,
    required AttachmentDownloadProgressCallback onProgress,
  }) {
    cancellations.add(cancellation);
    if (failNext) {
      failNext = false;
      return Future.error(StateError('download failed'));
    }
    _onProgress = onProgress;
    _completion = Completer<AttachmentDownloadResult?>();
    return _completion!.future;
  }

  void emit(AttachmentDownloadProgress progress) => _onProgress?.call(progress);

  void complete(AttachmentDownloadResult? result) {
    final completion = _completion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(result);
    }
  }
}
