import 'dart:io';

import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_discord_wire.dart';

const _channel = '300000000000000901';
const _author = '100000000000000902';
const _pinsPath = '/api/v9/channels/$_channel/messages/pins';

/// A user account's pins, read through the cache as the bot transport reads
/// them.
void main() {
  setUpAll(sqfliteFfiInit);

  test('pins read once show their authors offline', () async {
    var online = true;
    final transport = FakeDiscordTransport()
      ..on(
        'GET',
        _pinsPath,
        (_) => online ? jsonResponse(_pins()) : throw const SocketException(''),
      );
    final repository = await _repository(transport);
    await repository.loadPinnedMessages(_channel);

    online = false;
    final offline = await repository.loadPinnedMessages(_channel);

    expect(offline.messages.single.authorId, _author);
    expect(offline.members.map((member) => member.id), contains(_author));
  });

  test('a refused session reaches the caller, not the cached pins', () async {
    var refused = false;
    final transport = FakeDiscordTransport()
      ..on(
        'GET',
        _pinsPath,
        (_) => refused
            ? jsonResponse({'message': '401: Unauthorized'}, statusCode: 401)
            : jsonResponse(_pins()),
      );
    final repository = await _repository(transport);
    await repository.loadPinnedMessages(_channel);

    refused = true;

    await expectLater(
      repository.loadPinnedMessages(_channel),
      throwsA(
        isA<DiscordApiException>().having(
          (error) => error.isUnauthorized,
          'isUnauthorized',
          isTrue,
        ),
      ),
    );
  });
}

Map<String, Object?> _pins() => {
  'items': [
    {
      'pinned_at': '2026-07-25T11:00:00+00:00',
      'message': rawMessage(
        id: '400000000000000903',
        channelId: _channel,
        authorId: _author,
        content: 'Read the rules',
      ),
    },
  ],
  'has_more': false,
};

Future<DiscordDesktopChatRepository> _repository(
  FakeDiscordTransport transport,
) async {
  final cache = await SqliteChatCache.openAt(
    inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  final repository = DiscordDesktopChatRepository(
    DiscordDesktopApiClient(
      authorization: 'account-session',
      headers: const {},
      transport: transport,
    ),
    // Never dialled: pins are a REST route.
    DiscordDesktopGatewayClient(
      authorization: 'account-session',
      properties: const {'os': 'Windows'},
      socketConnector: MemoryDesktopWebSocketConnector(),
    ),
    cache,
  );
  addTearDown(repository.close);
  return repository;
}
