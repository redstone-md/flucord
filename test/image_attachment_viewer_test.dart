import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/attachment_download.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/attachment_download_controller.dart';
import 'package:flucord/src/presentation/widgets/image_attachment_viewer.dart';
import 'package:flucord/src/presentation/widgets/message_attachment_gallery.dart';
import 'package:flucord/src/presentation/widgets/message_attachment_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('opens from the timeline and closes with Escape', (tester) async {
    await tester.pumpWidget(
      _app(MessageAttachmentView(attachment: _imageAttachment)),
    );

    await tester.tap(
      find.byKey(const ValueKey('open-image-attachment-image-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('image-attachment-viewer')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('image-attachment-viewer')),
        matching: find.text('capture.png'),
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('image-attachment-viewer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zooms, resets, and remains usable at compact width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var closed = false;
    await tester.pumpWidget(
      _app(
        ImageAttachmentViewer(
          entries: const [
            ImageAttachmentViewerEntry(attachment: _imageAttachment),
          ],
          initialAttachmentId: _imageAttachment.id,
          onClose: () => closed = true,
          imageBuilder: (_, _) => const ColoredBox(
            key: ValueKey('fake-viewer-image'),
            color: Colors.blueGrey,
          ),
        ),
      ),
    );

    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('image-viewer-zoom-in')));
    await tester.pump();
    expect(find.text('125%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('image-viewer-reset')));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shares download progress with the viewer toolbar', (
    tester,
  ) async {
    final service = _FakeDownloadService();
    final controller = AttachmentDownloadController(
      attachment: _imageAttachment,
      service: service,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        ImageAttachmentViewer(
          entries: [
            ImageAttachmentViewerEntry(
              attachment: _imageAttachment,
              downloadController: controller,
            ),
          ],
          initialAttachmentId: _imageAttachment.id,
          onClose: () {},
          imageBuilder: (_, _) => const ColoredBox(color: Colors.blueGrey),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('download-image-viewer-attachment-image-1')),
    );
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey('cancel-download-image-viewer-attachment-image-1'),
      ),
      findsOneWidget,
    );

    service.emit(
      const AttachmentDownloadProgress(receivedBytes: 75, totalBytes: 100),
    );
    await tester.pump();
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      0.75,
    );

    service.complete(
      const AttachmentDownloadResult(
        path: r'C:\Downloads\capture.png',
        bytesWritten: 100,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('save-again-image-viewer-attachment-image-1')),
      findsOneWidget,
    );
    expect(find.text('Saved capture.png'), findsOneWidget);
  });

  testWidgets('navigates a gallery and resets zoom between images', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        ImageAttachmentViewer(
          entries: _galleryEntries,
          initialAttachmentId: _secondImage.id,
          onClose: () {},
          imageBuilder: (_, attachment) => ColoredBox(
            key: ValueKey('fake-viewer-${attachment.id}'),
            color: Colors.blueGrey,
          ),
        ),
      ),
    );

    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-viewer-image-2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('image-viewer-zoom-in')));
    await tester.pump();
    expect(find.text('125%'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-viewer-image-3')), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shares switched-image download state with its thumbnail', (
    tester,
  ) async {
    final service = _FakeDownloadService();
    await tester.pumpWidget(
      _app(
        MessageAttachmentGallery(
          attachments: const [_imageAttachment, _secondImage],
          downloadService: service,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('open-image-attachment-image-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('image-viewer-next')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('download-image-viewer-attachment-image-2')),
    );
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('cancel-download-image-viewer-attachment-image-2'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cancel-download-attachment-image-2')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('cancel-download-image-viewer-attachment-image-2'),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('download-attachment-image-2')),
      findsOneWidget,
    );
    service.complete(null);
  });

  testWidgets('rebuilds the registry when its download service changes', (
    tester,
  ) async {
    final firstService = _FakeDownloadService();
    final secondService = _FakeDownloadService();
    var service = firstService;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return MessageAttachmentGallery(
              attachments: const [_imageAttachment],
              downloadService: service,
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('download-attachment-image-1')));
    await tester.pump();
    expect(firstService.calls, 1);

    rebuild(() => service = secondService);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('download-attachment-image-1')));
    await tester.pump();
    expect(firstService.calls, 1);
    expect(secondService.calls, 1);
    secondService.complete(null);
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: FlucordTheme.dark,
  home: Scaffold(body: child),
);

const _imageAttachment = MessageAttachment(
  id: 'image-1',
  fileName: 'capture.png',
  url: 'https://cdn.discordapp.com/capture.png',
  size: 100,
  contentType: 'image/png',
  width: 1920,
  height: 1080,
);

const _secondImage = MessageAttachment(
  id: 'image-2',
  fileName: 'details.png',
  url: 'https://cdn.discordapp.com/details.png',
  size: 120,
  contentType: 'image/png',
  width: 1280,
  height: 720,
);

const _thirdImage = MessageAttachment(
  id: 'image-3',
  fileName: 'result.png',
  url: 'https://cdn.discordapp.com/result.png',
  size: 140,
  contentType: 'image/png',
  width: 800,
  height: 1200,
);

const _galleryEntries = [
  ImageAttachmentViewerEntry(attachment: _imageAttachment),
  ImageAttachmentViewerEntry(attachment: _secondImage),
  ImageAttachmentViewerEntry(attachment: _thirdImage),
];

final class _FakeDownloadService implements AttachmentDownloadService {
  Completer<AttachmentDownloadResult?>? _completion;
  AttachmentDownloadProgressCallback? _onProgress;
  int calls = 0;

  @override
  Future<AttachmentDownloadResult?> save(
    MessageAttachment attachment, {
    required AttachmentDownloadCancellation cancellation,
    required AttachmentDownloadProgressCallback onProgress,
  }) {
    calls++;
    _onProgress = onProgress;
    _completion = Completer<AttachmentDownloadResult?>();
    return _completion!.future;
  }

  void emit(AttachmentDownloadProgress progress) => _onProgress?.call(progress);

  void complete(AttachmentDownloadResult? result) =>
      _completion?.complete(result);
}
