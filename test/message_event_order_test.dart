import 'dart:async';

import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/presentation/widgets/message_list.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000001';
const _historyPath = '/api/v9/channels/${SessionHarness.channelId}/messages';
const _approveButton = ValueKey('component-approve-Approve');
const _heldRole = '400000000000000001';

Map<String, Object?> _message(
  String id,
  String content, {
  String timestamp = '2026-07-25T10:00:00+00:00',
}) => rawMessage(
  id: id,
  channelId: SessionHarness.channelId,
  guildId: SessionHarness.guildId,
  authorId: SessionHarness.friendId,
  content: content,
  timestamp: timestamp,
);

/// What Discord sends for a change that names only some fields, such as a pin
/// or an embed that finished loading.
Map<String, Object?> _partial(String id, Map<String, Object?> fields) => {
  'id': id,
  'channel_id': SessionHarness.channelId,
  'guild_id': SessionHarness.guildId,
  ...fields,
};

Map<String, Object?> _reaction(String messageId, String userId) => {
  'channel_id': SessionHarness.channelId,
  'guild_id': SessionHarness.guildId,
  'message_id': messageId,
  'user_id': userId,
  'emoji': const {'id': null, 'name': '🔥'},
};

Future<void> _burst(
  SessionHarness session,
  List<(String, Map<String, Object?>)> dispatches,
) async {
  for (final (event, data) in dispatches) {
    await session.dispatch(event, data, settle: false);
  }
  await session.settle();
}

/// Discord's newest page: a full 100 messages, newest first, so the app knows
/// that older ones exist.
List<Map<String, Object?>> _fullPageNewerThanTheOldMessage() => [
  for (var index = 99; index >= 0; index--)
    _message(
      _pageMessageId(index),
      'page message $index',
      timestamp: DateTime.utc(2026, 7, 25, 12, index).toIso8601String(),
    ),
];

String _pageMessageId(int index) => '91000000000000${100 + index}';

void main() {
  group('a deleted message stays deleted', () {
    testSession('when its create and delete land in one burst', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);

      await _burst(session, [
        ('MESSAGE_CREATE', _message(_messageId, 'gone soon')),
        ('MESSAGE_DELETE', _partial(_messageId, const {})),
      ]);

      expect(session.messageRow(_messageId), findsNothing);
      expect(await session.cachedMessage(_messageId), isNull);
    });

    testSession('when an update and its delete land in one burst', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch(
        'MESSAGE_CREATE',
        _message(_messageId, 'gone soon'),
      );

      await _burst(session, [
        ('MESSAGE_UPDATE', _message(_messageId, 'edited, then gone')),
        ('MESSAGE_DELETE', _partial(_messageId, const {})),
      ]);

      expect(session.messageRow(_messageId), findsNothing);
      expect(await session.cachedMessage(_messageId), isNull);
    });

    testSession('when a reaction and its delete land in one burst', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch(
        'MESSAGE_CREATE',
        _message(_messageId, 'gone soon'),
      );

      await _burst(session, [
        (
          'MESSAGE_REACTION_ADD',
          _reaction(_messageId, SessionHarness.friendId),
        ),
        ('MESSAGE_DELETE', _partial(_messageId, const {})),
      ]);

      expect(session.messageRow(_messageId), findsNothing);
      expect(await session.cachedMessage(_messageId), isNull);
    });

    testSession('when its create and a bulk delete land in one burst', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);

      await _burst(session, [
        ('MESSAGE_CREATE', _message(_messageId, 'gone soon')),
        (
          'MESSAGE_DELETE_BULK',
          const {
            'ids': [_messageId],
            'channel_id': SessionHarness.channelId,
            'guild_id': SessionHarness.guildId,
          },
        ),
      ]);

      expect(session.messageRow(_messageId), findsNothing);
      expect(await session.cachedMessage(_messageId), isNull);
    });
  });

  testSession('reactions that land together all reach the cache', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch('MESSAGE_CREATE', _message(_messageId, 'ship it'));

    await _burst(session, [
      for (final userId in ['2', '3', '4'])
        ('MESSAGE_REACTION_ADD', _reaction(_messageId, userId)),
    ]);

    final cached = await session.cachedMessage(_messageId);
    expect(cached!.reactions.single.count, 3);
  });

  testSession('a message that cannot be read does not stop the next one', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);

    await _burst(session, [
      // No author and no timestamp, so it cannot become a message.
      ('MESSAGE_CREATE', _partial('900000000000000002', const {})),
      ('MESSAGE_CREATE', _message(_messageId, 'still arrives')),
    ]);

    expect(session.messageRow(_messageId), findsOneWidget);
  });

  testSession('closing the app finishes the messages still in line', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    const lastIndex = 49;

    for (var index = 0; index <= lastIndex; index++) {
      await session.dispatch(
        'MESSAGE_CREATE',
        _message(_pageMessageId(index), 'message $index'),
        settle: false,
      );
    }
    await session.relaunch(ready: SessionHarness.defaultReady());

    expect(await session.cachedMessage(_pageMessageId(lastIndex)), isNotNull);
  }, onDisk: true);

  group('an update', () {
    testSession('to a message the timeline does not hold stays out of it', (
      tester,
      session,
    ) async {
      const oldId = '900000000000000050';
      session.transport.on(
        'GET',
        _historyPath,
        (_) => jsonResponse([
          _message(
            oldId,
            'old words',
            timestamp: DateTime.utc(2026, 7, 1).toIso8601String(),
          ),
        ]),
      );
      await session.openChannel(SessionHarness.channelId);
      // A later launch: the newest page no longer reaches the old message,
      // and only the cache still holds it.
      session.transport.on('GET', _historyPath, (request) {
        final isOlderPage = request.uri.queryParameters.containsKey('before');
        return jsonResponse(
          isOlderPage ? <Object?>[] : _fullPageNewerThanTheOldMessage(),
        );
      });
      await session.relaunch(ready: SessionHarness.defaultReady());
      await session.openChannel(SessionHarness.channelId);

      await session.dispatch(
        'MESSAGE_UPDATE',
        _message(
          oldId,
          'old words, edited',
          timestamp: DateTime.utc(2026, 7, 1).toIso8601String(),
        ),
      );
      // The top of the timeline asks for the page before its oldest message.
      await tester.drag(find.byType(MessageList), const Offset(0, 8000));
      await session.settle();

      expect(session.messageRow(oldId), findsNothing);
      expect(
        session.transport.requests
            .map((request) => request.uri.queryParameters['before'])
            .nonNulls,
        [_pageMessageId(0)],
      );
      expect((await session.cachedMessage(oldId))?.body, 'old words, edited');
    }, onDisk: true);

    testSession('to a message in neither place adds nothing', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);

      await session.dispatch(
        'MESSAGE_UPDATE',
        _message(_messageId, 'never held'),
      );

      expect(session.messageRow(_messageId), findsNothing);
      expect(await session.cachedMessage(_messageId), isNull);
    });

    testSession(
      'that still mentions a role the account holds keeps the mention',
      (tester, session) async {
        final mentionsHeldRole = {
          ..._message(_messageId, 'hey team'),
          'mentions': const <Object?>[],
          'mention_roles': const [_heldRole],
        };
        await session.openChannel(SessionHarness.channelId);
        await session.dispatch('MESSAGE_CREATE', mentionsHeldRole);

        await session.dispatch('MESSAGE_UPDATE', {
          ...mentionsHeldRole,
          'content': 'hey team, edited',
        });

        final cached = await session.cachedMessage(_messageId);
        expect(cached?.body, 'hey team, edited');
        expect(cached?.mentionsCurrentMember, isTrue);
      },
      ready: SessionHarness.defaultReady()
        ..['merged_members'] = [
          [
            {
              'user_id': SessionHarness.currentUserId,
              'roles': [_heldRole],
            },
          ],
        ],
    );

    testSession(
      'to an on-screen message missing from the cache still applies',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await session.dropCachedMessage(_messageId);

        await session.dispatch(
          'MESSAGE_UPDATE',
          _partial(_messageId, const {'content': 'fresh words'}),
        );

        expect(find.textContaining('fresh words'), findsOneWidget);
        expect(find.textContaining('stale words'), findsNothing);
      },
      routes: (transport) => transport.on(
        'GET',
        _historyPath,
        (_) => jsonResponse([_message(_messageId, 'stale words')]),
      ),
    );

    testSession(
      'that names only some fields keeps the buttons, here and after a restart',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await session.dispatch('MESSAGE_CREATE', {
          ..._message(_messageId, 'choose'),
          'mention_everyone': true,
          'components': const [
            {
              'type': 1,
              'components': [
                {
                  'type': 2,
                  'style': 1,
                  'label': 'Approve',
                  'custom_id': 'approve',
                },
              ],
            },
          ],
        });

        await session.dispatch(
          'MESSAGE_UPDATE',
          _partial(_messageId, const {'pinned': true}),
        );

        expect(find.byKey(_approveButton), findsOneWidget);
        final cached = await session.cachedMessage(_messageId);
        expect(cached?.isPinned, isTrue);
        expect(cached?.mentionsEveryone, isTrue);

        // Discord stays silent, so the screen reads the cached page.
        final neverAnswered = Completer<DiscordHttpResponse>();
        session.transport.on('GET', _historyPath, (_) => neverAnswered.future);
        await session.relaunch(ready: SessionHarness.defaultReady());
        await session.openChannel(SessionHarness.channelId);

        expect(find.byKey(_approveButton), findsOneWidget);
      },
      onDisk: true,
    );
  });

  group('on the bot transport', () {
    late _FakeGateway gateway;
    late SqliteChatCache cache;
    late DiscordChatRepository repository;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      gateway = _FakeGateway();
      cache = await SqliteChatCache.openAt(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      repository = DiscordChatRepository(
        DiscordApiClient(botToken: 'token', transport: FakeDiscordTransport()),
        gateway,
        cache,
      );
    });

    tearDown(() => repository.close());

    test('events keep their order and a delete has the last word', () async {
      final announced = <ChatRepositoryEvent>[];
      repository.events.listen(announced.add);

      for (final (name, data) in <(String, Map<String, Object?>)>[
        ('MESSAGE_CREATE', _message(_messageId, 'first')),
        ('MESSAGE_UPDATE', _message(_messageId, 'second')),
        ('MESSAGE_DELETE', _partial(_messageId, const {})),
      ]) {
        gateway.emit(DiscordGatewayDispatch(name: name, data: data));
      }
      await repository.events.firstWhere((e) => e is MessageDeletedEvent);

      expect(await cache.readMessage(_messageId), isNull);
      expect(announced.map((event) => event.runtimeType), const [
        MessageUpsertedEvent,
        MessageUpdatedEvent,
        MessageDeletedEvent,
      ]);
    });

    test('an update does not put an old message in the timeline', () async {
      final announced = <ChatRepositoryEvent>[];
      repository.events.listen(announced.add);
      gateway.emit(
        DiscordGatewayDispatch(
          name: 'MESSAGE_CREATE',
          data: _message(_messageId, 'first'),
        ),
      );
      await repository.events.first;

      gateway.emit(
        DiscordGatewayDispatch(
          name: 'MESSAGE_UPDATE',
          data: _partial(_messageId, const {'content': 'second'}),
        ),
      );
      await repository.events.first;

      expect(announced.last, isA<MessageUpdatedEvent>());
      expect((await cache.readMessage(_messageId))?.body, 'second');
    });
  });
}

final class _FakeGateway implements DiscordChatGateway {
  final StreamController<DiscordGatewayEvent> _events =
      StreamController.broadcast();

  void emit(DiscordGatewayEvent event) => _events.add(event);

  @override
  Stream<DiscordGatewayEvent> get events => _events.stream;

  @override
  String? get sessionId => 'session-1';

  @override
  Future<void> connect(String gatewayUrl) async {}

  @override
  void updateVoiceState({
    required String guildId,
    required String? channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) {}

  @override
  void pingVoiceServer() {}

  @override
  Future<void> close() => _events.close();
}
