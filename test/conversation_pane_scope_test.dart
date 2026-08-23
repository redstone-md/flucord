import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/app_composition.dart';
import 'package:flucord/src/application/voice_channel_surface.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/channel_capabilities.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';
import 'package:flucord/src/presentation/conversation_pane.dart';
import 'package:flucord/src/presentation/widgets/attachment_download_scope.dart';
import 'package:flucord/src/presentation/widgets/chat_scope.dart';
import 'package:flucord/src/presentation/widgets/direct_call_scope.dart';
import 'package:flucord/src/presentation/widgets/expression_favorites_scope.dart';
import 'package:flucord/src/presentation/widgets/external_link_launcher_scope.dart';
import 'package:flucord/src/presentation/widgets/gif_picker_scope.dart';
import 'package:flucord/src/presentation/widgets/go_live_scope.dart';
import 'package:flucord/src/presentation/widgets/message_component_scope.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';
import 'package:flucord/src/presentation/widgets/message_list.dart';
import 'package:flucord/src/presentation/widgets/remote_camera_scope.dart';
import 'package:flucord/src/presentation/widgets/slash_command_scope.dart';
import 'package:flucord/src/presentation/widgets/soundboard_scope.dart';
import 'package:flucord/src/presentation/widgets/stage_scope.dart';
import 'package:flucord/src/presentation/widgets/stream_viewer_scope.dart';
import 'package:flucord/src/presentation/widgets/thread_membership_scope.dart';
import 'package:flucord/src/presentation/widgets/voice_message_recorder_scope.dart';
import 'package:flucord/src/presentation/widgets/voice_room_view.dart';
import 'package:flucord/src/presentation/widgets/voice_scope.dart';
import 'package:flucord/src/presentation/widgets/workspace_scope.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

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
          body: _paneHarness(
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
          body: _paneHarness(
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
          body: _paneHarness(
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
}

/// The scope nest the app builds above the pane, rebuilt here from the same
/// composition so the pane is exercised exactly as production wires it.
Widget _paneHarness(
  AppComposition composition,
  ChatWorkspace workspace, {
  required ConversationChannel channel,
  ChannelCapabilities capabilities = ChannelCapabilities.unrestricted,
}) => ChatScope(
  controller: composition.chat,
  child: WorkspaceScope(
    controller: composition.workspace,
    child: DirectCallScope(
      controller: composition.directCall,
      child: ExternalLinkLauncherScope(
        launcher: composition.externalLinkLauncher,
        child: AttachmentDownloadScope(
          service: composition.attachmentDownload,
          child: VoiceMessageRecorderScope(
            recorder: composition.voiceMessageRecorder,
            child: ThreadMembershipScope(
              controller: composition.threadMembership,
              child: StageScope(
                controller: composition.stage,
                child: SoundboardScope(
                  controller: composition.soundboard,
                  child: GoLiveScope(
                    controller: composition.goLive,
                    child: StreamViewerScope(
                      controller: composition.streamViewer,
                      child: RemoteCameraScope(
                        controller: composition.remoteCameras,
                        child: GifPickerScope(
                          controller: composition.gifPicker,
                          child: ExpressionFavoritesScope(
                            controller: composition.expressionFavorites,
                            child: SlashCommandScope(
                              controller: composition.slashCommand,
                              child: MessageComponentScope(
                                controller: composition.messageComponent,
                                child: VoiceScope(
                                  controller: composition.voice,
                                  child: ConversationPane(
                                    workspace: workspace,
                                    capabilities: capabilities,
                                    channel: channel,
                                    channels: WorkspacePermissions(
                                      workspace,
                                    ).visibleChannelsFor(channel.spaceId),
                                    compact: false,
                                    allowMemberPanel: true,
                                    allowThreadPanel: true,
                                    showMembers: false,
                                    showPins: false,
                                    showThreads: false,
                                    onPickChannel: (_) {},
                                    onSelectChannel: (_) {},
                                    onOpenInbox: () {},
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
