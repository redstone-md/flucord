import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/domain/discord_permissions.dart';

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
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
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
