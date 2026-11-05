import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// FLUCORD-96: the profile card shows the banner, bio and pronouns the person
// set for the server it opens in, and falls back to their global ones.

const _forgeMessage = '900000000000000061';
const _playMessage = '900000000000000062';
const _playId = '200000000000000002';
const _playChannelId = '300000000000000070';

const _profilePath = '/api/v9/users/${SessionHarness.friendId}/profile';

final _card = find.byKey(const ValueKey('profile-card'));
final _bannerImage = find.byKey(const ValueKey('profile-card-banner-image'));

/// The default READY plus a second server, Play&day, with one channel.
Map<String, Object?> _twoServers() {
  final ready = SessionHarness.defaultReady();
  final guilds = ready['guilds']! as List;
  final forge = guilds.first as Map<String, Object?>;
  final everyone = (forge['roles']! as List).first as Map<String, Object?>;
  guilds.add(
    rawGuild(
      id: _playId,
      name: 'Play&day',
      channels: [rawChannel(id: _playChannelId, name: 'lobby')],
      everyonePermissions: everyone['permissions']! as String,
    ),
  );
  return ready;
}

/// Opens the friend's card from a message of theirs in [channelId].
Future<void> _openCard(
  WidgetTester tester,
  SessionHarness session, {
  String space = SessionHarness.guildId,
  String channelId = SessionHarness.channelId,
  String messageId = _forgeMessage,
}) async {
  await session.openChannel(channelId, space: space);
  if (session.messageRow(messageId).evaluate().isEmpty) {
    await session.dispatch(
      'MESSAGE_CREATE',
      rawMessage(
        id: messageId,
        channelId: channelId,
        guildId: space,
        authorId: SessionHarness.friendId,
        content: 'hello',
      ),
    );
  }
  await tester.tap(
    find.descendant(
      of: session.messageRow(messageId),
      matching: find.byKey(const ValueKey('message-author-name')),
    ),
  );
  await session.settle();
  expect(_card, findsOneWidget);
}

Future<void> _closeCard(WidgetTester tester, SessionHarness session) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await session.settle();
  expect(_card, findsNothing);
}

String _bannerUrl(WidgetTester tester) =>
    (tester.widget<Image>(_bannerImage).image as NetworkImage).url;

Finder _inCard(String text) => find.descendant(
  of: _card,
  matching: find.textContaining(text, findRichText: true),
);

Iterable<RecordedRequest> _profileReads(SessionHarness session) =>
    session.transport.requests.where(
      (request) => request.method == 'GET' && request.uri.path == _profilePath,
    );

/// The profile route as Discord answers it: the server profile only comes
/// back when the request names a server.
void Function(FakeDiscordTransport) _profileRoute({
  Map<String, Object?> user = const {},
  Map<String, Object?> userProfile = const {},
  Map<String, Map<String, Object?>> serverProfiles = const {},
}) =>
    (transport) => transport.on('GET', _profilePath, (request) {
      final guildId = request.uri.queryParameters['guild_id'];
      final server = serverProfiles[guildId];
      return jsonResponse({
        'user': {'id': SessionHarness.friendId, 'username': 'friend', ...user},
        'user_profile': userProfile,
        if (server != null)
          'guild_member_profile': {'guild_id': guildId, ...server},
      });
    });

void main() {
  testSession(
    'a card opened in a server shows that server profile',
    (tester, session) async {
      await _openCard(tester, session);

      expect(
        _profileReads(session).single.uri.queryParameters['guild_id'],
        SessionHarness.guildId,
      );
      expect(
        _bannerUrl(tester),
        'https://cdn.discordapp.com/guilds/200000000000000001/users/'
        '100000000000000002/banners/forgebanner.webp?size=512',
      );
      expect(_inCard('Forge regular'), findsOneWidget);
      expect(_inCard('he/him'), findsOneWidget);
      expect(_inCard('Global bio'), findsNothing);
    },
    routes: _profileRoute(
      user: {'banner': 'globalbanner'},
      userProfile: {
        'bio': 'Global bio',
        'pronouns': 'they/them',
        'banner': 'globalbanner',
      },
      serverProfiles: {
        SessionHarness.guildId: {
          'bio': 'Forge regular',
          'pronouns': 'he/him',
          'banner': 'forgebanner',
        },
      },
    ),
  );

  testSession(
    'a banner image is as tall as in Discord\'s popout',
    (tester, session) async {
      await _openCard(tester, session);

      // Discord's popout is 300 px wide with a 105 px banner image.
      expect(tester.getSize(_card).width, 300);
      expect(
        tester.getSize(find.byKey(const ValueKey('profile-card-banner'))),
        const Size(300, 105),
      );
    },
    routes: _profileRoute(userProfile: {'banner': 'globalbanner'}),
  );

  testSession(
    'the same person shows each server its own profile',
    (tester, session) async {
      await _openCard(tester, session);
      expect(_bannerUrl(tester), contains('/banners/forgebanner.'));
      expect(_inCard('Forge regular'), findsOneWidget);
      await _closeCard(tester, session);

      await _openCard(
        tester,
        session,
        space: _playId,
        channelId: _playChannelId,
        messageId: _playMessage,
      );

      expect(
        _bannerUrl(tester),
        'https://cdn.discordapp.com/guilds/$_playId/users/'
        '100000000000000002/banners/playbanner.webp?size=512',
      );
      expect(_inCard('Lobby after nine'), findsOneWidget);
      expect(_inCard('Forge regular'), findsNothing);
    },
    ready: _twoServers(),
    routes: _profileRoute(
      serverProfiles: {
        SessionHarness.guildId: {
          'bio': 'Forge regular',
          'banner': 'forgebanner',
        },
        _playId: {'bio': 'Lobby after nine', 'banner': 'playbanner'},
      },
    ),
  );

  testSession(
    'the global banner shows where the server profile has none',
    (tester, session) async {
      await _openCard(tester, session);

      expect(
        _bannerUrl(tester),
        'https://cdn.discordapp.com/banners/100000000000000002/'
        'globalbanner.webp?size=512',
      );
      expect(_inCard('Forge regular'), findsOneWidget);
    },
    routes: _profileRoute(
      userProfile: {'banner': 'globalbanner'},
      serverProfiles: {
        SessionHarness.guildId: {'bio': 'Forge regular', 'banner': null},
      },
    ),
  );

  testSession(
    'an animated banner holds still, and plays as an animated WebP on hover',
    (tester, session) async {
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await _openCard(tester, session);
      await pointer.moveTo(Offset.zero);
      await tester.pump();
      const banner =
          'https://cdn.discordapp.com/banners/100000000000000002/a_moving.webp';
      expect(_bannerUrl(tester), '$banner?size=512');

      await pointer.moveTo(tester.getCenter(_bannerImage));
      await tester.pump();

      // What Discord's client loads: no banner comes as a GIF any more.
      expect(_bannerUrl(tester), '$banner?size=512&animated=true');
    },
    routes: _profileRoute(userProfile: {'banner': 'a_moving'}),
  );

  testSession(
    'a banner only on the user object still shows',
    (tester, session) async {
      await _openCard(tester, session);

      expect(
        _bannerUrl(tester),
        'https://cdn.discordapp.com/banners/100000000000000002/'
        'userbanner.webp?size=512',
      );
    },
    routes: _profileRoute(
      user: {'banner': 'userbanner'},
      userProfile: {'bio': 'Global bio', 'banner': null},
    ),
  );

  testSession('after a rate limit, the next open loads the banner', (
    tester,
    session,
  ) async {
    var limited = true;
    session.transport.on('GET', _profilePath, (_) {
      if (limited) {
        limited = false;
        return jsonResponse({
          'message': 'You are being rate limited.',
          'retry_after': 60,
          'global': false,
        }, statusCode: 429);
      }
      return jsonResponse({
        'user': {'id': SessionHarness.friendId, 'username': 'friend'},
        'user_profile': {'banner': 'globalbanner'},
      });
    });

    await _openCard(tester, session);
    expect(_bannerImage, findsNothing);
    await _closeCard(tester, session);

    await _openCard(tester, session);

    expect(_profileReads(session), hasLength(2));
    expect(_bannerUrl(tester), contains('/banners/100000000000000002/'));
  });

  for (final status in [403, 404]) {
    testSession(
      'a $status shows the card without a profile, and is not asked again',
      (tester, session) async {
        session.transport.on(
          'GET',
          _profilePath,
          (_) => jsonResponse({'message': 'Unknown User'}, statusCode: status),
        );

        await _openCard(tester, session);
        expect(_bannerImage, findsNothing);
        await _closeCard(tester, session);
        await _openCard(tester, session);

        expect(_profileReads(session), hasLength(1));
      },
    );
  }
}
