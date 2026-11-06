import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/message_flag_repository.dart';
import 'package:flucord/src/domain/message_forward_repository.dart';
import 'package:flucord/src/domain/sticker_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_discord_wire.dart';

const _account = '100000000000000001';
const _source = '200000000000000002';
const _target = '300000000000000003';
const _message = '400000000000000004';
const _forward = '500000000000000005';
const _sticker = '600000000000000006';

/// The message actions a user account takes over its own desktop routes, as
/// Userdoccers lists them: each test reads back the request Discord gets.
void main() {
  setUpAll(sqfliteFfiInit);

  group('forward', () {
    test('posts a forward reference to the target channel', () async {
      final transport = FakeDiscordTransport()
        ..on(
          'POST',
          '/api/v9/channels/$_target/messages',
          (_) => jsonResponse({
            ...rawMessage(
              id: _forward,
              channelId: _target,
              authorId: _account,
              content: '',
            ),
            'message_reference': {
              'type': 1,
              'message_id': _message,
              'channel_id': _source,
            },
            'message_snapshots': [
              {
                'message': {
                  'content': 'Ship the slice',
                  'timestamp': '2026-07-25T10:00:00+00:00',
                },
              },
            ],
          }),
        );
      final repository = await _repository(transport);

      final forwarded = await (repository as MessageForwardRepository)
          .forwardMessage(
            sourceChannelId: _source,
            sourceMessageId: _message,
            targetChannelId: _target,
          );

      final request = transport.requests.last;
      expect(request.method, 'POST');
      final body = request.json! as Map<String, Object?>;
      expect(body['message_reference'], {
        'type': 1,
        'message_id': _message,
        'channel_id': _source,
      });
      expect(body['content'], '');
      expect(body['nonce'], isA<String>());
      expect(forwarded.isForwarded, isTrue);
      expect(forwarded.snapshots.single.body, 'Ship the slice');
    });

    test('a refusal reaches the caller as Discord said it', () async {
      final transport = FakeDiscordTransport()
        ..on(
          'POST',
          '/api/v9/channels/$_target/messages',
          (_) => jsonResponse({
            'message': 'Missing Permissions',
            'code': 50013,
          }, statusCode: 403),
        );
      final repository = await _repository(transport);

      await expectLater(
        (repository as MessageForwardRepository).forwardMessage(
          sourceChannelId: _source,
          sourceMessageId: _message,
          targetChannelId: _target,
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

  group('stickers', () {
    test('posts the sticker ids with no words', () async {
      final transport = FakeDiscordTransport()
        ..on(
          'POST',
          '/api/v9/channels/$_target/messages',
          (_) => jsonResponse({
            ...rawMessage(
              id: _forward,
              channelId: _target,
              authorId: _account,
              content: '',
            ),
            'sticker_items': [
              {'id': _sticker, 'name': 'Wave', 'format_type': 1},
            ],
          }),
        );
      final repository = await _repository(transport);

      final sent = await (repository as StickerRepository).sendStickers(
        channelId: _target,
        authorId: _account,
        stickerIds: [_sticker],
      );

      final body = transport.requests.last.json! as Map<String, Object?>;
      expect(body['sticker_ids'], [_sticker]);
      expect(body['content'], '');
      expect(body.containsKey('message_reference'), isFalse);
      expect(sent.stickers.single.id, _sticker);
    });

    test('a sticker Discord will not send is refused aloud', () async {
      final transport = FakeDiscordTransport()
        ..on(
          'POST',
          '/api/v9/channels/$_target/messages',
          (_) => jsonResponse({
            'message': 'Invalid sticker sent',
            'code': 50081,
          }, statusCode: 400),
        );
      final repository = await _repository(transport);

      await expectLater(
        (repository as StickerRepository).sendStickers(
          channelId: _target,
          authorId: _account,
          stickerIds: [_sticker],
        ),
        throwsA(
          isA<DiscordApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            400,
          ),
        ),
      );
    });
  });

  group('suppress embeds', () {
    const path = '/api/v9/channels/$_source/messages/$_message';

    Map<String, Object?> edited({required int flags}) => {
      ...rawMessage(
        id: _message,
        channelId: _source,
        authorId: _account,
        content: 'https://example.com',
      ),
      'flags': flags,
      'embeds': const <Object?>[],
    };

    test('edits the flag on, and off again', () async {
      final transport = FakeDiscordTransport()
        ..on('PATCH', path, (request) {
          final flags = (request.json! as Map)['flags']! as int;
          return jsonResponse(edited(flags: flags));
        });
      final flags = (await _repository(transport)) as MessageFlagRepository;

      final suppressed = await flags.setSuppressEmbeds(
        channelId: _source,
        messageId: _message,
        suppress: true,
      );
      expect(transport.requests.last.method, 'PATCH');
      expect(transport.requests.last.json, {'flags': 4});
      expect(suppressed.suppressesEmbeds, isTrue);

      final restored = await flags.setSuppressEmbeds(
        channelId: _source,
        messageId: _message,
        suppress: false,
      );
      expect(transport.requests.last.json, {'flags': 0});
      expect(restored.suppressesEmbeds, isFalse);
    });

    test('a components message keeps its own flag', () async {
      const componentsV2 = 1 << 15;
      final transport = FakeDiscordTransport()
        ..on(
          'GET',
          '/api/v9/channels/$_source/messages',
          (_) => jsonResponse([edited(flags: componentsV2)]),
        )
        ..on(
          'PATCH',
          path,
          (_) => jsonResponse(edited(flags: componentsV2 | 4)),
        );
      final repository = await _repository(transport);
      await repository.loadChannelHistory(_source);

      await (repository as MessageFlagRepository).setSuppressEmbeds(
        channelId: _source,
        messageId: _message,
        suppress: true,
      );

      expect(transport.requests.last.json, {'flags': componentsV2 | 4});
    });

    test('a message this account may not edit is refused aloud', () async {
      final transport = FakeDiscordTransport()
        ..on(
          'PATCH',
          path,
          (_) => jsonResponse({
            'message': 'Missing Permissions',
            'code': 50013,
          }, statusCode: 403),
        );
      final repository = await _repository(transport);

      await expectLater(
        (repository as MessageFlagRepository).setSuppressEmbeds(
          channelId: _source,
          messageId: _message,
          suppress: true,
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
