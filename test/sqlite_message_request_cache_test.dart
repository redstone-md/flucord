import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/v25_cache.dart';

const _requestId = 'dm-request';
const _acceptedId = 'dm-accepted';

ConversationChannel _dm(
  String id, {
  bool request = false,
  DateTime? requestedAt,
}) => ConversationChannel(
  id: id,
  spaceId: CommunitySpace.directMessagesId,
  name: id,
  topic: '',
  kind: ChannelKind.text,
  recipientIds: ['user-$id'],
  isMessageRequest: request,
  messageRequestedAt: requestedAt,
);

void main() {
  setUpAll(sqfliteFfiInit);

  test('a cached message request stays a request, with its time', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final requestedAt = DateTime.utc(2026, 11, 3, 18, 30);

    await cache.writeWorkspace(
      ChatWorkspace(
        spaces: const [CommunitySpace.directMessages()],
        channels: [
          _dm(_requestId, request: true, requestedAt: requestedAt),
          _dm(_acceptedId),
        ],
        members: const [],
        messages: const [],
        currentMemberId: 'me',
      ),
    );
    final restored = (await cache.readWorkspace())!;

    final request = restored.channelById(_requestId);
    expect(request.isMessageRequest, isTrue);
    expect(request.messageRequestedAt, requestedAt);
    final accepted = restored.channelById(_acceptedId);
    expect(accepted.isMessageRequest, isFalse);
    expect(accepted.messageRequestedAt, isNull);
  });

  test('a channel cached before v26 opens as no request', () async {
    final path = await writeV25DirectMessage(
      channelId: _acceptedId,
      recipientId: 'user-1',
    );

    final cache = await SqliteChatCache.openAt(
      path,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final channel = (await cache.readWorkspaceShell())!.channelById(
      _acceptedId,
    );

    expect(channel.isMessageRequest, isFalse);
    expect(channel.messageRequestedAt, isNull);
  });
}
