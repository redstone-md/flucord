import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/message_attachment_view.dart';
import 'package:flucord/src/presentation/widgets/native_voice_message_player.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets(
    'routes Discord audio metadata through the native voice boundary',
    (tester) async {
      final waveform = base64Encode(const [12, 64, 128, 255]);
      String? source;
      Duration? capturedDuration;
      String? capturedWaveform;
      await tester.pumpWidget(
        _TestApp(
          child: MessageAttachmentView(
            attachment: MessageAttachment(
              id: 'audio-1',
              fileName: 'voice-message.ogg',
              url: 'https://cdn.discordapp.com/voice-message.ogg',
              size: 4096,
              contentType: 'audio/ogg',
              durationSecs: 12.75,
              waveform: waveform,
            ),
            inlineVoiceBuilder:
                ({required url, required duration, required waveform, key}) {
                  source = url;
                  capturedDuration = duration;
                  capturedWaveform = waveform;
                  return SizedBox(key: key, width: 280, height: 64);
                },
          ),
        ),
      );

      expect(source, 'https://cdn.discordapp.com/voice-message.ogg');
      expect(capturedDuration, const Duration(milliseconds: 12750));
      expect(capturedWaveform, waveform);
      expect(find.byKey(const ValueKey('attachment-audio-audio-1')), findsOne);
    },
  );

  test('decodes Discord base64 waveform bytes into normalized samples', () {
    final samples = DiscordVoiceWaveform.decode(
      base64Encode(const [0, 128, 255]),
    );

    expect(samples, hasLength(3));
    expect(samples.first, 0.08);
    expect(samples[1], closeTo(128 / 255, 0.001));
    expect(samples.last, 1);
    expect(DiscordVoiceWaveform.decode('%%%'), isEmpty);
  });

  testWidgets('voice controls expose play, waveform seek, and compact time', (
    tester,
  ) async {
    var playbackToggles = 0;
    double? soughtFraction;
    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: 260,
          child: VoiceMessageControls(
            state: const VoiceMessageViewState(
              position: Duration(seconds: 10),
              duration: Duration(seconds: 20),
              isBuffering: false,
            ),
            samples: const [0.2, 0.6, 1, 0.4],
            onTogglePlayback: () => playbackToggles++,
            onSeekFraction: (value) => soughtFraction = value,
          ),
        ),
      ),
    );

    expect(find.text('00:10'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('voice-message-player'))).width,
      260,
    );
    await tester.tap(find.byTooltip('Play voice message'));
    final waveform = find.byKey(const ValueKey('voice-message-waveform'));
    final rect = tester.getRect(waveform);
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));

    expect(playbackToggles, 1);
    expect(soughtFraction, closeTo(0.75, 0.02));
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
