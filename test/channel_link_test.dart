import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/channel_link.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';

void main() {
  group('ChannelLink', () {
    test('round-trips a workspace channel', () {
      const link = ChannelLink(
        spaceId: '123456789012345678',
        channelId: '987654321098765432',
      );

      expect(ChannelLink.tryParse(link.toUri().toString()), link);
      expect(
        link.toUri().toString(),
        'flucord://channels/123456789012345678/987654321098765432',
      );
    });

    test('rejects unrelated or ambiguous routes', () {
      expect(ChannelLink.tryParse('https://channels/space/channel'), isNull);
      expect(ChannelLink.tryParse('flucord://members/space/channel'), isNull);
      expect(ChannelLink.tryParse('flucord://channels/space'), isNull);
      expect(
        ChannelLink.tryParse('flucord://channels/space/channel?token=x'),
        isNull,
      );
    });
  });

  test('workspace opens a valid link atomically', () async {
    final workspace = await MockChatRepository(
      latency: Duration.zero,
    ).loadWorkspace();
    final controller = WorkspaceController();
    addTearDown(controller.dispose);
    controller.reconcile(workspace);
    controller.setQuery('stale search');

    final opened = controller.openChannelLink(
      workspace,
      const ChannelLink(spaceId: 'night', channelId: 'night-ops'),
    );

    expect(opened, isTrue);
    expect(controller.selectedSpaceId, 'night');
    expect(controller.selectedChannelId, 'night-ops');
    expect(controller.query, isEmpty);
    expect(
      controller.openChannelLink(
        workspace,
        const ChannelLink(spaceId: 'forge', channelId: 'night-ops'),
      ),
      isFalse,
    );
  });
}
