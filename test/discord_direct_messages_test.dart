import 'package:flucord/src/data/discord/discord_direct_messages.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _me = '100000000000000001';
const _groupId = '400000000000000031';
const _dmId = '400000000000000041';

const _friend = {'id': '100000000000000002', 'username': 'friend'};
const _newcomer = {'id': '100000000000000032', 'username': 'newcomer'};

void main() {
  setUpAll(sqfliteFfiInit);

  test('a recipient change keeps the newest message of the group', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final events = <ChatRepositoryEvent>[];
    final mapper = DiscordMapper();
    final directMessages = DiscordDirectMessages(
      (_) => throw UnimplementedError('No DM is opened here'),
      cache,
      mapper,
      events.add,
    );
    final ready = {
      'id': _groupId,
      'type': 3,
      'last_message_id': '410000000000000031',
      'recipients': [_friend],
    };
    directMessages.seed(
      [mapper.directMessage(ready, _me)!.channel],
      payloads: [ready],
    );

    await directMessages.acceptMessage({
      'id': '600000000000000031',
      'channel_id': _groupId,
      'channel_type': 3,
      'author': _friend,
    }, _me);
    await directMessages.acceptRecipientChange(
      {'channel_id': _groupId, 'user': _newcomer},
      _me,
      added: true,
    );

    final group = events
        .whereType<ChannelUpsertedEvent>()
        .map((event) => event.channel)
        .last;
    expect(group.recipientIds, contains(_newcomer['id']));
    expect(group.lastMessageId, '600000000000000031');
  });

  test('a DM closed here comes back when the account sends from another '
      'client', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final events = <ChatRepositoryEvent>[];
    final mapper = DiscordMapper();
    final directMessages = DiscordDirectMessages(
      (_) => throw UnimplementedError('No DM is opened here'),
      cache,
      mapper,
      events.add,
    );
    final ready = {
      'id': _dmId,
      'type': 1,
      'recipients': [_friend],
    };
    directMessages
      ..seed([mapper.directMessage(ready, _me)!.channel], payloads: [ready])
      ..forget(_dmId);

    await directMessages.acceptMessage({
      'id': '600000000000000041',
      'channel_id': _dmId,
      'channel_type': 1,
      'author': {'id': _me, 'username': 'me'},
    }, _me);

    final reopened = events.whereType<ChannelUpsertedEvent>().single.channel;
    expect(reopened.id, _dmId);
    expect(reopened.recipientIds, [_friend['id']]);
  });
}
