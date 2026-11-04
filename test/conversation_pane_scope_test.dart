import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/app_composition.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/application/voice_channel_surface.dart';
import 'package:flucord/src/data/disconnected_chat_repository.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/channel_capabilities.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';
import 'package:flucord/src/presentation/widgets/message_list.dart';
import 'package:flucord/src/presentation/widgets/voice_room_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/fake_voice_message_recorder.dart';
import 'support/pane_harness.dart';

/// Pumps the pane the way the app does: scopes above it, data and intents as
/// its parameters, nothing else. This is the pane's contract, so a controller
/// that creeps back into the constructor list has to break this test to get
/// there.
void main() {
  testWidgets('a text channel shows the timeline and the composer', (
    tester,
  ) async {
    final composition = AppComposition(AppBootstrap.demo());
    addTearDown(composition.dispose);
    final workspace = await MockChatRepository(
      latency: Duration.zero,
    ).loadWorkspace();
    composition.workspace
      ..reconcile(workspace)
      ..selectChannel('forge-general');

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: paneHarness(
            composition,
            workspace,
            channel: workspace.channelById('forge-general'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(find.byType(MessageList), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a voice channel shows the room, and the chat on its surface', (
    tester,
  ) async {
    final composition = AppComposition(AppBootstrap.demo());
    addTearDown(composition.dispose);
    final workspace = await MockChatRepository(
      latency: Duration.zero,
    ).loadWorkspace();
    composition.workspace
      ..reconcile(workspace)
      ..selectChannel('forge-voice');

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: paneHarness(
            composition,
            workspace,
            channel: workspace.channelById('forge-voice'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The room is the default surface: no composer until the switch flips.
    expect(find.byType(VoiceRoomView), findsOneWidget);
    expect(find.byKey(const ValueKey('message-composer')), findsNothing);

    composition.workspace.selectVoiceSurface(
      'forge-voice',
      VoiceChannelSurface.chat,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a channel without send permission stops at the notice', (
    tester,
  ) async {
    final composition = AppComposition(AppBootstrap.demo());
    addTearDown(composition.dispose);
    final workspace = await MockChatRepository(
      latency: Duration.zero,
    ).loadWorkspace();
    composition.workspace
      ..reconcile(workspace)
      ..selectChannel('forge-general');

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: paneHarness(
            composition,
            workspace,
            channel: workspace.channelById('forge-general'),
            capabilities: ChannelCapabilities.none,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReadOnlyChannelNotice), findsOneWidget);
    expect(find.byKey(const ValueKey('message-composer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (session, bootstrap, offered) in [
    (
      'a session that sends voice messages',
      AppBootstrap(
        initialSessionMode: SessionMode.demo,
        voiceMessageRecorder: FakeVoiceMessageRecorder(),
      ),
      true,
    ),
    (
      'a session that cannot send voice messages',
      AppBootstrap(
        initialRepository: const DisconnectedChatRepository(),
        voiceMessageRecorder: FakeVoiceMessageRecorder(),
      ),
      false,
    ),
  ]) {
    testWidgets('$session ${offered ? 'offers' : 'offers no'} microphone', (
      tester,
    ) async {
      final composition = AppComposition(bootstrap);
      addTearDown(composition.dispose);
      final workspace = await MockChatRepository(
        latency: Duration.zero,
      ).loadWorkspace();
      composition.workspace
        ..reconcile(workspace)
        ..selectChannel('forge-general');

      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: paneHarness(
              composition,
              workspace,
              channel: workspace.channelById('forge-general'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('record-voice-message')),
        offered ? findsOneWidget : findsNothing,
      );
    });
  }
}
