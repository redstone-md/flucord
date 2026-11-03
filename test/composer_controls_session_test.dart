import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/data/discord/discord_frecency_proto.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/proto/proto_message.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/expression_favorites.dart';
import 'package:flucord/src/theme/flucord_icons.dart';

import 'support/fake_discord_wire.dart';
import 'support/fake_voice_message_recorder.dart';
import 'support/session_harness.dart';

final _sendPath = '/api/v9/channels/${SessionHarness.channelId}/messages';

void main() {
  testSession('a click at the centre of Send sends the message', (
    tester,
    session,
  ) async {
    session.transport.on(
      'POST',
      _sendPath,
      (_) => jsonResponse(
        rawMessage(
          id: '900000000000000001',
          channelId: SessionHarness.channelId,
          guildId: SessionHarness.guildId,
          authorId: SessionHarness.currentUserId,
          content: 'hello',
        ),
      ),
    );
    await session.openChannel(SessionHarness.channelId);
    expect(find.byKey(const ValueKey('gif-picker-open')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'hello',
    );
    await session.settle();
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await session.settle();

    final sent = session.transport.requests.where(
      (request) => request.method == 'POST' && request.uri.path == _sendPath,
    );
    expect(sent.single.json, containsPair('content', 'hello'));
  });

  final recorder = FakeVoiceMessageRecorder();
  testSession(
    'a click at the centre of the voice message button starts recording',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      await tester.tap(find.byKey(const ValueKey('record-voice-message')));
      await session.settle();

      expect(recorder.startCount, 1);
      expect(find.byKey(const ValueKey('message-composer')), findsNothing);
    },
    voiceMessageRecorder: recorder,
  );

  for (final width in [360.0, 600.0, 940.0, 1280.0]) {
    testSession(
      'every control sits inside the field at a window $width wide',
      (tester, session) async {
        // Opening the server shows its first channel, and a narrow window has
        // no sidebar to pick one from.
        await tester.tap(
          find.byKey(const ValueKey('space-${SessionHarness.guildId}')),
        );
        await session.settle();
        await tester.enterText(
          find.byKey(const ValueKey('message-composer')),
          'hello',
        );
        await session.settle();

        final field = tester.getRect(
          find.byKey(const ValueKey('message-composer')),
        );
        for (final key in const [
          'composer-menu',
          'open-emoji-picker',
          'gif-picker-open',
          'open-sticker-picker',
          'send-message',
        ]) {
          final control = find.byKey(ValueKey(key));
          expect(
            field.contains(tester.getCenter(control)),
            isTrue,
            reason: key,
          );
          expect(
            tester
                .hitTestOnBinding(tester.getCenter(control))
                .path
                .any((entry) => entry.target == tester.renderObject(control)),
            isTrue,
            reason: key,
          );
        }
      },
      size: Size(width, 700),
    );
  }

  group('slash commands', () {
    Future<void> type(WidgetTester tester, String text) =>
        tester.enterText(find.byKey(const ValueKey('message-composer')), text);

    // Past the debounce the controller waits for before it asks Discord.
    Future<void> waitForList(
      WidgetTester tester,
      SessionHarness session,
    ) async {
      await tester.pump(const Duration(milliseconds: 250));
      await session.settle();
    }

    Iterable<RecordedRequest> posted(SessionHarness session, String path) =>
        session.transport.requests.where(
          (request) => request.method == 'POST' && request.uri.path == path,
        );

    testSession('typing a slash lists commands, and a click runs one', (
      tester,
      session,
    ) async {
      _routeCommands(session);
      await session.openChannel(SessionHarness.channelId);

      await type(tester, '/');
      await waitForList(tester, session);
      expect(find.text('/ping'), findsOneWidget);

      await tester.tap(find.text('/ping'));
      await session.settle();

      final interaction = posted(session, '/api/v9/interactions').single;
      expect((interaction.json! as Map)['data'], containsPair('name', 'ping'));
      expect(posted(session, _sendPath), isEmpty);
      expect(find.byKey(const ValueKey('slash-command-list')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('message-composer')))
            .controller
            ?.text,
        isEmpty,
      );
    });

    testSession('Enter runs the first command and posts no text', (
      tester,
      session,
    ) async {
      _routeCommands(session);
      await session.openChannel(SessionHarness.channelId);

      await type(tester, '/ping');
      await session.settle();
      // The answer has not come yet, and that is no reason to post the text.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await session.settle();
      expect(posted(session, _sendPath), isEmpty);

      await waitForList(tester, session);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await session.settle();

      expect(posted(session, '/api/v9/interactions'), hasLength(1));
      expect(posted(session, _sendPath), isEmpty);
    });

    testSession('a list from the last channel is not offered in the next', (
      tester,
      session,
    ) async {
      _routeCommands(session);
      session.transport.on(
        'GET',
        '/api/v9/channels/${SessionHarness.otherChannelId}/application-commands/search',
        (_) => jsonResponse({'application_commands': <Object?>[]}),
      );
      await session.openChannel(SessionHarness.channelId);
      await type(tester, '/');
      await waitForList(tester, session);
      expect(find.text('/ping'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('channel-${SessionHarness.otherChannelId}')),
      );
      await session.settle();
      await type(tester, '/');
      await waitForList(tester, session);

      expect(find.text('/ping'), findsNothing);
    });

    testSession('a slash no command matches still goes out as text', (
      tester,
      session,
    ) async {
      session.transport.on(
        'GET',
        _commandSearchPath,
        (_) => jsonResponse({'application_commands': <Object?>[]}),
      );
      session.transport.on(
        'POST',
        _sendPath,
        (_) => jsonResponse(
          rawMessage(
            id: '900000000000000001',
            channelId: SessionHarness.channelId,
            guildId: SessionHarness.guildId,
            authorId: SessionHarness.currentUserId,
            content: '/shrug',
          ),
        ),
      );
      await session.openChannel(SessionHarness.channelId);

      await type(tester, '/shrug');
      await waitForList(tester, session);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await session.settle();

      expect(posted(session, _sendPath), hasLength(1));
      expect(find.byKey(const ValueKey('slash-command-list')), findsNothing);
    });
  });

  group('favourites', () {
    const gifUrl = 'https://tenor.example/starred';
    const stickerId = '600000000000000001';
    const emojiId = '600000000000000002';

    void routeFavourites(FakeDiscordTransport transport) => transport.on(
      'GET',
      '/api/v9/users/@me/settings-proto/2',
      (_) => jsonResponse({
        'settings': base64.encode(
          DiscordFrecencyProtoCodec.apply(
            ProtoMessage(),
            const ExpressionFavorites(
              gifs: [FavoriteGif(url: gifUrl, src: gifUrl)],
              stickerIds: [stickerId],
              emojis: [emojiId],
            ),
          ).encode(),
        ),
      }),
    );

    // A server's emoji and stickers arrive inside its entry in READY.
    Map<String, Object?> readyWithExpressions() => SessionHarness.defaultReady()
      ..['guilds'] = [
        {
          ...rawGuild(
            id: SessionHarness.guildId,
            name: 'The Forge',
            channels: [
              rawChannel(id: SessionHarness.channelId, name: 'general'),
            ],
            everyonePermissions:
                '${DiscordPermissions.viewChannel | DiscordPermissions.sendMessages}',
          ),
          'emojis': [
            {'id': emojiId, 'name': 'forge'},
          ],
          'stickers': [
            {'id': stickerId, 'name': 'wave', 'format_type': 1, 'tags': 'hi'},
          ],
        },
      ];

    testSession(
      'show in the emoji picker',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        await tester.tap(find.byKey(const ValueKey('open-emoji-picker')));
        await session.settle();

        expect(find.text('FAVOURITES'), findsOneWidget);
      },
      routes: routeFavourites,
      ready: readyWithExpressions(),
    );

    // Trending is not routed here: a picker with nothing else keeps the stars.
    testSession('show in the GIF picker', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      await tester.tap(find.byKey(const ValueKey('gif-picker-open')));
      await session.settle();

      expect(
        find.byKey(const ValueKey('gif-favorite-$gifUrl')),
        findsOneWidget,
      );
    }, routes: routeFavourites);

    testSession(
      'show in the sticker picker',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);

        await tester.tap(find.byKey(const ValueKey('open-sticker-picker')));
        await session.settle();

        expect(
          find.descendant(
            of: find.byKey(const ValueKey('sticker-star-$stickerId')),
            matching: find.byIcon(Icons.star),
          ),
          findsOneWidget,
        );
      },
      routes: routeFavourites,
      ready: readyWithExpressions(),
    );
  });

  testSession('a poll is created from the menu', (tester, session) async {
    await session.openChannel(SessionHarness.channelId);

    await tester.tap(find.byKey(const ValueKey('composer-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-poll')));
    await tester.pumpAndSettle();

    expect(find.text('Create a poll'), findsOneWidget);
  });

  testSession('silent send from the menu goes out with the silent flag', (
    tester,
    session,
  ) async {
    session.transport.on(
      'POST',
      _sendPath,
      (_) => jsonResponse(
        rawMessage(
          id: '900000000000000001',
          channelId: SessionHarness.channelId,
          guildId: SessionHarness.guildId,
          authorId: SessionHarness.currentUserId,
          content: 'quiet',
        ),
      ),
    );
    await session.openChannel(SessionHarness.channelId);

    await tester.tap(find.byKey(const ValueKey('composer-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send-silently')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('composer-silent-notice')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'quiet',
    );
    await session.settle();
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await session.settle();

    final sent = session.transport.requests.singleWhere(
      (request) => request.method == 'POST' && request.uri.path == _sendPath,
    );
    expect(sent.json, containsPair('flags', 4096));
    expect(find.byKey(const ValueKey('composer-silent-notice')), findsNothing);
  });

  testSession(
    'a channel that denies ATTACH_FILES shows no attach button',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      expect(find.byTooltip('Add attachment'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is FlucordIcon && widget.icon == FlucordIcons.attach,
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('composer-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('add-attachment')), findsNothing);
      expect(find.byKey(const ValueKey('create-poll')), findsOneWidget);
    },
    ready: SessionHarness.defaultReady()
      // Without the account's member record the client cannot judge permissions
      // and allows everything, so this READY has to carry one.
      ..['users'] = [
        {'id': SessionHarness.currentUserId, 'username': 'me'},
      ]
      ..['private_channels'] = <Object?>[]
      ..['merged_members'] = [
        [
          {'user_id': SessionHarness.currentUserId, 'roles': <String>[]},
        ],
      ]
      ..['guilds'] = [
        rawGuild(
          id: SessionHarness.guildId,
          name: 'The Forge',
          channels: [
            {
              ...rawChannel(id: SessionHarness.channelId, name: 'general'),
              'permission_overwrites': [
                {
                  'id': SessionHarness.guildId,
                  'type': 0,
                  'allow': '0',
                  'deny': '${DiscordPermissions.attachFiles}',
                },
              ],
            },
          ],
          everyonePermissions:
              '${DiscordPermissions.viewChannel | DiscordPermissions.sendMessages | DiscordPermissions.readMessageHistory | DiscordPermissions.attachFiles}',
        ),
      ],
  );
}

const _commandSearchPath =
    '/api/v9/channels/${SessionHarness.channelId}/application-commands/search';

void _routeCommands(SessionHarness session) {
  session.transport.on(
    'GET',
    _commandSearchPath,
    (_) => jsonResponse({
      'application_commands': [
        {
          'id': '700000000000000001',
          'application_id': '700000000000000002',
          'version': '700000000000000003',
          'name': 'ping',
          'description': 'Checks the bot',
          'type': 1,
        },
      ],
    }),
  );
  session.transport.on(
    'POST',
    '/api/v9/interactions',
    (_) => const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
  );
}
