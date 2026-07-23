import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('history merge preserves guild-specific member identity', () {
    final workspace = ChatWorkspace(
      spaces: const [],
      channels: const [],
      members: const [
        Member(
          id: 'user-1',
          displayName: 'Guild name',
          initials: 'GN',
          role: 'Operator',
          presence: Presence.online,
          colorValue: 0xff456b5a,
          spaceIds: {'guild-1'},
          rolesBySpace: {'guild-1': 'Operator'},
          avatarUrl: 'https://cdn.example/global-old.webp',
          avatarUrlsBySpace: {
            'guild-1': 'https://cdn.example/guild-avatar.webp',
          },
        ),
      ],
      messages: const [],
      currentMemberId: 'user-1',
    );
    final merged = workspace.mergeHistory(
      ChannelHistory(
        channelId: 'channel-1',
        messages: const [],
        members: const [
          Member(
            id: 'user-1',
            displayName: 'Global name',
            initials: 'GN',
            role: 'Member',
            presence: Presence.offline,
            colorValue: 0xff456b5a,
            avatarUrl: 'https://cdn.example/global-new.webp',
          ),
        ],
      ),
    );

    final member = merged.members.single;
    expect(member.avatarUrl, endsWith('global-new.webp'));
    expect(member.avatarUrlFor('guild-1'), endsWith('guild-avatar.webp'));
    expect(member.roleFor('guild-1'), 'Operator');
    expect(member.presence, Presence.online);
  });
}
