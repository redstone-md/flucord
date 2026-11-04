import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/v25_cache.dart';

const _groupId = 'group-1';
const _iconUrl = 'https://cdn.discordapp.com/channel-icons/group-1/a1.webp';

void main() {
  setUpAll(sqfliteFfiInit);

  test('a cached group DM keeps every recipient and its picture', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);

    await cache.writeWorkspace(
      ChatWorkspace(
        spaces: const [CommunitySpace.directMessages()],
        channels: const [
          ConversationChannel(
            id: _groupId,
            spaceId: CommunitySpace.directMessagesId,
            name: 'Raid night',
            topic: '',
            kind: ChannelKind.text,
            recipientIds: ['user-1', 'user-2'],
            isGroupDirectMessage: true,
            iconUrl: _iconUrl,
          ),
          ConversationChannel(
            id: 'duo',
            spaceId: CommunitySpace.directMessagesId,
            name: 'Duo',
            topic: '',
            kind: ChannelKind.text,
            recipientIds: ['user-1'],
            isGroupDirectMessage: true,
          ),
        ],
        members: const [],
        messages: const [],
        currentMemberId: 'me',
      ),
    );
    final restored = (await cache.readWorkspace())!;
    final group = restored.channelById(_groupId);

    expect(group.recipientIds, ['user-1', 'user-2']);
    expect(group.iconUrl, _iconUrl);
    expect(group.isGroupDirectMessage, isTrue);
    final duo = restored.channelById('duo');
    expect(duo.isGroupDirectMessage, isTrue);
    expect(duo.soleRecipientId, isNull);
  });

  test('a DM cached before v27 keeps its one recipient', () async {
    final path = await writeV25DirectMessage(
      channelId: 'dm-1',
      recipientId: 'user-1',
    );

    final cache = await SqliteChatCache.openAt(
      path,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final channel = (await cache.readWorkspaceShell())!.channelById('dm-1');

    expect(channel.soleRecipientId, 'user-1');
    expect(channel.isGroupDirectMessage, isFalse);
    expect(channel.iconUrl, isNull);
  });
}
