import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/message_attachment_view.dart';
import 'package:flucord/src/presentation/widgets/native_inline_video_player.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('renders video attachments through the native video boundary', (
    tester,
  ) async {
    String? source;
    double? ratio;
    await tester.pumpWidget(
      _TestApp(
        child: MessageAttachmentView(
          attachment: const MessageAttachment(
            id: 'video-1',
            fileName: 'release.mp4',
            url: 'https://cdn.discordapp.com/release.mp4',
            size: 4096,
            contentType: 'video/mp4',
            width: 1920,
            height: 1080,
          ),
          inlineVideoBuilder: ({required url, required aspectRatio, key}) {
            source = url;
            ratio = aspectRatio;
            return SizedBox(key: key, width: 320, height: 180);
          },
        ),
      ),
    );

    expect(source, 'https://cdn.discordapp.com/release.mp4');
    expect(ratio, closeTo(16 / 9, 0.001));
    expect(find.byKey(const ValueKey('attachment-video-video-1')), findsOne);
  });

  test('recognizes common video extensions when content type is absent', () {
    const attachment = MessageAttachment(
      id: 'video-2',
      fileName: 'capture.WEBM',
      url: 'https://cdn.discordapp.com/capture.webm',
      size: 1024,
    );

    expect(attachment.isVideo, isTrue);
    expect(attachment.isImage, isFalse);
  });

  testWidgets('video controls expose playback, mute, seek, and fullscreen', (
    tester,
  ) async {
    var playbackToggles = 0;
    var muteToggles = 0;
    var fullscreenToggles = 0;
    Duration? soughtTo;
    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: 420,
          child: InlineVideoControls(
            state: const InlineVideoViewState(
              position: Duration(seconds: 30),
              duration: Duration(minutes: 2),
            ),
            onTogglePlayback: () => playbackToggles++,
            onToggleMute: () => muteToggles++,
            onSeek: (value) => soughtTo = value,
            onFullscreen: () => fullscreenToggles++,
          ),
        ),
      ),
    );

    expect(find.text('00:30 / 02:00'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('inline-video-controls')))
          .height,
      44,
    );

    await tester.tap(find.byTooltip('Play'));
    await tester.tap(find.byTooltip('Mute'));
    await tester.tap(find.byTooltip('Fullscreen'));
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('inline-video-seek')),
    );
    slider.onChanged!(90000);

    expect(playbackToggles, 1);
    expect(muteToggles, 1);
    expect(fullscreenToggles, 1);
    expect(soughtTo, const Duration(seconds: 90));
    expect(tester.takeException(), isNull);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  );
}
