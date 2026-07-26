import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/channel_link.dart';
import 'package:flucord/src/application/voice_channel_surface.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  group('VoiceChannelSurfaces', () {
    test('defaults to the room and reports real transitions', () {
      final surfaces = VoiceChannelSurfaces();

      expect(surfaces.of('forge-voice'), VoiceChannelSurface.room);
      expect(surfaces.select('forge-voice', VoiceChannelSurface.room), isFalse);
      expect(surfaces.select('forge-voice', VoiceChannelSurface.chat), isTrue);
      expect(surfaces.of('forge-voice'), VoiceChannelSurface.chat);
      expect(surfaces.select('forge-voice', VoiceChannelSurface.chat), isFalse);
      expect(surfaces.select('forge-voice', VoiceChannelSurface.room), isTrue);
      expect(surfaces.of('forge-voice'), VoiceChannelSurface.room);
    });

    test('keeps one surface per channel and prunes departed channels', () {
      final surfaces = VoiceChannelSurfaces()
        ..select('forge-voice', VoiceChannelSurface.chat)
        ..select('night-radio', VoiceChannelSurface.chat);

      surfaces.retainAll(const ['forge-voice', 'forge-general']);

      expect(surfaces.of('forge-voice'), VoiceChannelSurface.chat);
      expect(surfaces.of('night-radio'), VoiceChannelSurface.room);
    });
  });

  group('WorkspaceController voice surfaces', () {
    test('keeps the room unless a caller asks for the chat', () async {
      final workspace = await MockChatRepository(
        latency: Duration.zero,
      ).loadWorkspace();
      final controller = WorkspaceController();
      var notifications = 0;
      controller
        ..reconcile(workspace)
        ..addListener(() => notifications++);

      controller.selectChannel('forge-voice');
      expect(
        controller.voiceSurfaceOf('forge-voice'),
        VoiceChannelSurface.room,
      );
      expect(notifications, 1);

      controller.selectChannel('forge-voice');
      expect(notifications, 1);

      controller.selectChannel(
        'forge-voice',
        surface: VoiceChannelSurface.chat,
      );
      expect(
        controller.voiceSurfaceOf('forge-voice'),
        VoiceChannelSurface.chat,
      );
      expect(notifications, 2);
    });

    test('toggles the surface without moving the selection', () async {
      final workspace = await MockChatRepository(
        latency: Duration.zero,
      ).loadWorkspace();
      final controller = WorkspaceController()..reconcile(workspace);
      var notifications = 0;
      controller
        ..selectChannel('forge-voice')
        ..addListener(() => notifications++)
        ..selectVoiceSurface('forge-voice', VoiceChannelSurface.chat);

      expect(controller.selectedChannelId, 'forge-voice');
      expect(
        controller.voiceSurfaceOf('forge-voice'),
        VoiceChannelSurface.chat,
      );
      expect(notifications, 1);

      controller.selectVoiceSurface('forge-voice', VoiceChannelSurface.chat);
      expect(notifications, 1);
    });

    test('message-shaped navigation lands on the chat surface', () async {
      final workspace = await MockChatRepository(
        latency: Duration.zero,
      ).loadWorkspace();
      final controller = WorkspaceController()..reconcile(workspace);

      controller.selectMessage('forge-voice', 'm12');
      expect(
        controller.voiceSurfaceOf('forge-voice'),
        VoiceChannelSurface.chat,
      );
      expect(controller.targetMessageId, 'm12');

      controller.selectVoiceSurface('night-radio', VoiceChannelSurface.room);
      final opened = controller.openChannelLink(
        workspace,
        const ChannelLink(spaceId: 'night', channelId: 'night-radio'),
      );

      expect(opened, isTrue);
      expect(
        controller.voiceSurfaceOf('night-radio'),
        VoiceChannelSurface.chat,
      );
      expect(controller.selectedChannelId, 'night-radio');
    });

    test('forgets surfaces for channels the workspace dropped', () async {
      final workspace = await MockChatRepository(
        latency: Duration.zero,
      ).loadWorkspace();
      final controller = WorkspaceController()
        ..reconcile(workspace)
        ..selectVoiceSurface('forge-voice', VoiceChannelSurface.chat);

      controller.reconcile(workspace.removeChannel('forge-voice'));

      expect(
        controller.voiceSurfaceOf('forge-voice'),
        VoiceChannelSurface.room,
      );
    });

    test('never lands on a voice channel by default', () async {
      final workspace = await MockChatRepository(
        latency: Duration.zero,
      ).loadWorkspace();
      final controller = WorkspaceController()..reconcile(workspace);

      controller.selectSpace(workspace, 'night');

      expect(controller.selectedChannelId, 'night-ops');
      expect(
        workspace.channelById(controller.selectedChannelId!).kind,
        isNot(ChannelKind.voice),
      );
    });
  });
}
