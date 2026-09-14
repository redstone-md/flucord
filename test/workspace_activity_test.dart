import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/workspace_activity.dart';

void main() {
  test('aggregates unread and mention state by space in one projection', () {
    final activity = _workspace.activityBySpace();

    expect(activity, hasLength(2));
    expect(activity['guild-1']?.unread, isTrue);
    expect(activity['guild-1']?.mentionCount, 5);
    expect(activity['guild-1']?.hasUnread, isTrue);
    expect(activity[CommunitySpace.directMessagesId]?.unread, isFalse);
    expect(activity[CommunitySpace.directMessagesId]?.mentionCount, 1);
    expect(activity[CommunitySpace.directMessagesId]?.hasUnread, isTrue);
    expect(activity['quiet-guild'], isNull);
  });

  test('returns immutable activity without entries for quiet channels', () {
    final activity = _workspace.activityBySpace();

    expect(
      () => activity['new-space'] = SpaceActivity.none,
      throwsUnsupportedError,
    );
    expect(SpaceActivity.none.hasUnread, isFalse);
  });
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace.directMessages(),
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff5865f2,
    ),
    CommunitySpace(
      id: 'quiet-guild',
      name: 'Quiet',
      monogram: 'Q',
      colorValue: 0xff5865f2,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'guild-general',
      spaceId: 'guild-1',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
      unread: true,
      mentionCount: 2,
    ),
    ConversationChannel(
      id: 'guild-thread',
      spaceId: 'guild-1',
      name: 'release',
      topic: '',
      kind: ChannelKind.text,
      isThread: true,
      mentionCount: 3,
    ),
    ConversationChannel(
      id: 'dm-1',
      spaceId: CommunitySpace.directMessagesId,
      name: 'Jack',
      topic: '',
      kind: ChannelKind.text,
      recipientId: 'user-1',
      mentionCount: 1,
    ),
    ConversationChannel(
      id: 'quiet-general',
      spaceId: 'quiet-guild',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  members: const [],
  messages: const [],
  currentMemberId: 'bot-1',
);
