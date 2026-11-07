import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/reaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_discord_wire.dart';

const _channel = '300000000000000003';
const _message = '400000000000000004';
const _reactor = '100000000000000002';
const _emoji = 'forge spark:123';
const _reactionsPath =
    '/api/v9/channels/$_channel/messages/$_message/reactions/'
    'forge%20spark%3A123';

/// The reaction routes a user account takes, as Userdoccers lists them: each
/// test reads back the request Discord gets.
void main() {
  setUpAll(sqfliteFfiInit);

  test('lists who reacted, one reaction type at a time', () async {
    final transport = FakeDiscordTransport()
      ..on(
        'GET',
        _reactionsPath,
        (_) => jsonResponse([
          {'id': _reactor, 'username': 'jack', 'global_name': 'Jack'},
        ]),
      );
    final repository = await _repository(transport);

    final page = await (repository as ReactionRepository).loadReactionUsers(
      channelId: _channel,
      messageId: _message,
      emoji: _emoji,
      type: DiscordReactionType.burst,
      afterUserId: '100',
      limit: 25,
    );

    final request = transport.requests.last;
    expect(request.method, 'GET');
    expect(request.uri.path, _reactionsPath);
    expect(request.uri.queryParameters, {
      'type': '1',
      'after': '100',
      'limit': '25',
    });
    expect(page.users.single.displayName, 'Jack');
    expect(page.hasMore, isFalse);
  });

  group('super reaction', () {
    test('is added with the burst type on the own-reaction route', () async {
      final transport = FakeDiscordTransport()
        ..on(
          'PUT',
          '$_reactionsPath/@me',
          (_) => jsonResponse(null, statusCode: 204),
        );
      final repository = await _repository(transport);

      await (repository as SuperReactionRepository).addSuperReaction(
        channelId: _channel,
        messageId: _message,
        emoji: _emoji,
      );

      final request = transport.requests.last;
      expect(request.method, 'PUT');
      expect(request.uri.path, '$_reactionsPath/@me');
      expect(request.uri.queryParameters, {'type': '1'});
    });

    test('is taken back on the route that names the burst type', () async {
      final transport = FakeDiscordTransport()
        ..on(
          'DELETE',
          '$_reactionsPath/1/@me',
          (_) => jsonResponse(null, statusCode: 204),
        );
      final repository = await _repository(transport);

      await (repository as SuperReactionRepository).removeSuperReaction(
        channelId: _channel,
        messageId: _message,
        emoji: _emoji,
      );

      final request = transport.requests.last;
      expect(request.method, 'DELETE');
      expect(request.uri.path, '$_reactionsPath/1/@me');
    });

    test('a normal reaction keeps its own routes', () async {
      final transport = FakeDiscordTransport()
        ..on(
          'PUT',
          '$_reactionsPath/@me',
          (_) => jsonResponse(null, statusCode: 204),
        )
        ..on(
          'DELETE',
          '$_reactionsPath/@me',
          (_) => jsonResponse(null, statusCode: 204),
        );
      final repository = await _repository(transport);

      await repository.addReaction(
        channelId: _channel,
        messageId: _message,
        emoji: _emoji,
      );
      await repository.removeReaction(
        channelId: _channel,
        messageId: _message,
        emoji: _emoji,
      );

      final [added, removed] = transport.requests.sublist(
        transport.requests.length - 2,
      );
      expect(added.method, 'PUT');
      expect(added.uri.path, '$_reactionsPath/@me');
      expect(added.uri.queryParameters, isEmpty);
      expect(removed.method, 'DELETE');
      expect(removed.uri.path, '$_reactionsPath/@me');
    });

    test('a refusal reaches the caller as Discord said it', () async {
      final transport = FakeDiscordTransport()
        ..on(
          'PUT',
          '$_reactionsPath/@me',
          (_) => jsonResponse({
            'message': 'Missing Permissions',
            'code': 50013,
          }, statusCode: 403),
        );
      final repository = await _repository(transport);

      await expectLater(
        (repository as SuperReactionRepository).addSuperReaction(
          channelId: _channel,
          messageId: _message,
          emoji: _emoji,
        ),
        throwsA(
          isA<DiscordApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            403,
          ),
        ),
      );
    });
  });
}

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
    // Never dialled: these are REST routes, and the repository only needs a
    // gateway to exist.
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
