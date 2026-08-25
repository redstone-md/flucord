import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/message_attachment_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('an inline preview is fetched and decoded at its drawn size', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_photo));

    final image = _previewImage(tester);
    final resized = image.image as ResizeImage;
    final source = resized.imageProvider as NetworkImage;
    final requested = Uri.parse(source.url);
    final scale = tester.view.devicePixelRatio;

    expect(requested.host, 'media.discordapp.net');
    expect(requested.path, '/attachments/channel-1/photo-1/photo.png');
    expect(
      requested.queryParameters['width'],
      '${(MessageAttachmentView.previewSize.width * scale).round()}',
    );
    expect(
      requested.queryParameters['height'],
      '${(MessageAttachmentView.previewSize.height * scale).round()}',
    );
    expect(
      resized.width,
      (MessageAttachmentView.previewSize.width * scale).round(),
    );
    expect(
      resized.height,
      (MessageAttachmentView.previewSize.height * scale).round(),
    );
  });

  testWidgets('a preview with no proxy falls back to the original host', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_photoWithoutProxy));

    final image = _previewImage(tester);
    final resized = image.image as ResizeImage;
    final source = resized.imageProvider as NetworkImage;

    expect(source.url, _photoWithoutProxy.url);
    expect(resized.width, isNotNull);
  });
}

Image _previewImage(WidgetTester tester) => tester.widget<Image>(
  find.descendant(
    of: find.byType(MessageAttachmentView),
    matching: find.byType(Image),
  ),
);

Widget _host(MessageAttachment attachment) => MaterialApp(
  theme: FlucordTheme.dark,
  home: Scaffold(
    body: Center(child: MessageAttachmentView(attachment: attachment)),
  ),
);

const _photo = MessageAttachment(
  id: 'photo-1',
  fileName: 'photo.png',
  url: 'https://cdn.discordapp.com/attachments/channel-1/photo-1/photo.png',
  proxyUrl:
      'https://media.discordapp.net/attachments/channel-1/photo-1/photo.png',
  size: 4000000,
  contentType: 'image/png',
  width: 4000,
  height: 3000,
);

const _photoWithoutProxy = MessageAttachment(
  id: 'photo-2',
  fileName: 'photo.png',
  url: 'https://cdn.discordapp.com/attachments/channel-1/photo-2/photo.png',
  size: 4000000,
  contentType: 'image/png',
  width: 4000,
  height: 3000,
);
