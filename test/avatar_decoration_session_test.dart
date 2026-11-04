import 'package:flucord/src/domain/accessibility.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// FLUCORD-107: avatar decorations show on avatars wherever Discord shows
// them, still until hovered.

const _messageId = '900000000000000081';
const _friendAsset = 'a_8f1c0e2b7d4a6c9e3b5f1a0d2c4e6b8a';
const _ownAsset = '3c5e7a9b1d2f4a6c8e0b2d4f6a8c0e1b';
const _decorationSku = '1144058844004233369';

const _presets = 'https://cdn.discordapp.com/avatar-decoration-presets';
const _friendStill = '$_presets/$_friendAsset.png?size=96&passthrough=false';
const _friendMoving = '$_presets/$_friendAsset.png?size=96&passthrough=true';
const _ownStill = '$_presets/$_ownAsset.png?size=96';

final _dmRow = find.byKey(
  const ValueKey('channel-${SessionHarness.dmChannelId}'),
);
final _accountPanel = find.byKey(const ValueKey('account-panel'));

Map<String, Object?> _decoration(String asset) => {
  'asset': asset,
  'sku_id': _decorationSku,
  'expires_at': null,
};

/// READY where the friend wears an animated decoration and the account a
/// still one.
Map<String, Object?> _ready() => SessionHarness.defaultReady()
  ..['user'] = {
    'id': SessionHarness.currentUserId,
    'username': 'me',
    'avatar_decoration_data': _decoration(_ownAsset),
  }
  ..['users'] = [
    {
      'id': SessionHarness.friendId,
      'username': 'friend',
      'global_name': 'Friend',
      'avatar_decoration_data': _decoration(_friendAsset),
    },
  ];

/// The decoration [surface] draws on [userId]'s avatar now, or null.
String? _decorationIn(
  WidgetTester tester,
  Finder surface, {
  String userId = SessionHarness.friendId,
}) {
  final image = find.descendant(
    of: surface,
    matching: find.byKey(ValueKey('member-avatar-decoration-$userId')),
  );
  if (image.evaluate().isEmpty) return null;
  return (tester.widget<Image>(image).image as NetworkImage).url;
}

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _openDirectMessages(WidgetTester tester, SessionHarness session) =>
    session.openChannel(SessionHarness.dmChannelId, space: 'direct-messages');

void main() {
  testSession(
    'the DM list holds the decoration still until the row is hovered',
    (tester, session) async {
      await _openDirectMessages(tester, session);
      expect(_decorationIn(tester, _dmRow), _friendStill);

      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(_dmRow));
      await tester.pump();
      expect(_decorationIn(tester, _dmRow), _friendMoving);

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(_decorationIn(tester, _dmRow), _friendStill);
    },
    ready: _ready(),
  );

  testSession(
    'a hovered decoration stays still under reduced motion',
    (tester, session) async {
      await _openDirectMessages(tester, session);
      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(_dmRow));
      await tester.pump();

      expect(_decorationIn(tester, _dmRow), _friendStill);
    },
    ready: _ready(),
    accessibility: const AccessibilitySettings(reducedMotion: true),
  );

  testSession('the account panel shows the account\'s own decoration', (
    tester,
    session,
  ) async {
    expect(
      _decorationIn(
        tester,
        _accountPanel,
        userId: SessionHarness.currentUserId,
      ),
      _ownStill,
    );
  }, ready: _ready());

  testSession('a message row reads the decoration from the message author', (
    tester,
    session,
  ) async {
    await _openDirectMessages(tester, session);
    await session.dispatch(
      'MESSAGE_CREATE',
      rawMessage(
          id: _messageId,
          channelId: SessionHarness.dmChannelId,
          authorId: SessionHarness.friendId,
          content: 'hi',
        )
        ..['author'] = {
          'id': SessionHarness.friendId,
          'username': 'friend',
          'avatar_decoration_data': _decoration(_friendAsset),
        },
    );

    expect(_decorationIn(tester, session.messageRow(_messageId)), _friendStill);
  });

  testSession(
    'the member list reads the decoration from the member list update',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch('GUILD_MEMBER_LIST_UPDATE', {
        'guild_id': SessionHarness.guildId,
        'id': 'everyone',
        'member_count': 1,
        'online_count': 1,
        'groups': [
          {'id': 'online', 'count': 1},
        ],
        'ops': [
          {
            'op': 'SYNC',
            'range': [0, 99],
            'items': [
              {
                'group': {'id': 'online', 'count': 1},
              },
              {
                'member': {
                  'user': {
                    'id': SessionHarness.friendId,
                    'username': 'friend',
                    'avatar_decoration_data': _decoration(_friendAsset),
                  },
                  'roles': <Object?>[],
                  'presence': {'status': 'online'},
                },
              },
            ],
          },
        ],
      });

      expect(
        _decorationIn(
          tester,
          find.byKey(const ValueKey('member-row-${SessionHarness.friendId}')),
        ),
        _friendStill,
      );
    },
  );

  testSession('a presence update that takes the decoration off removes it', (
    tester,
    session,
  ) async {
    await _openDirectMessages(tester, session);
    expect(_decorationIn(tester, _dmRow), isNotNull);

    await session.dispatch('PRESENCE_UPDATE', {
      'status': 'online',
      'activities': <Object?>[],
      'user': {
        'id': SessionHarness.friendId,
        'username': 'friend',
        'avatar_decoration_data': null,
      },
    });

    expect(_decorationIn(tester, _dmRow), isNull);
  }, ready: _ready());

  testSession('an avatar without a decoration draws none', (
    tester,
    session,
  ) async {
    await _openDirectMessages(tester, session);

    expect(_decorationIn(tester, _dmRow), isNull);
  });
}
