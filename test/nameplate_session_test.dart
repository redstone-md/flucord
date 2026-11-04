import 'package:flucord/src/presentation/widgets/nameplate_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000031';
// Light enough to read on every dark surface, so it is drawn as given.
const _red = Color(0xffff9999);

Map<String, Object?> _ready() => SessionHarness.defaultReady()
  ..['users'] = [
    {
      'id': SessionHarness.friendId,
      'username': 'friend',
      'global_name': 'Friend',
      'collectibles': {
        'nameplate': {
          'asset': 'nameplates/nameplates/twilight/',
          'palette': 'cobalt',
          'sku_id': '1349849614353829990',
          'label': '',
        },
      },
      'display_name_styles': {
        'colors': [0xff9999],
        'font_id': 11,
        'effect_id': 1,
      },
    },
  ];

/// A friend's nameplate and name style, from READY to the screen, and gone
/// again once a presence update says they took them off.
void main() {
  testSession(
    'the DM list and DM messages show them until a presence clears them',
    (tester, session) async {
      await session.openChannel(
        SessionHarness.dmChannelId,
        space: 'direct-messages',
      );
      await session.dispatch(
        'MESSAGE_CREATE',
        rawMessage(
          id: _messageId,
          channelId: SessionHarness.dmChannelId,
          authorId: SessionHarness.friendId,
          content: 'hi',
        ),
      );
      final row = find.byKey(
        const ValueKey('channel-${SessionHarness.dmChannelId}'),
      );
      Finder backdrop() =>
          find.descendant(of: row, matching: find.byType(NameplateBackdrop));
      Color? authorColor() => tester
          .widget<Text>(
            find.descendant(
              of: find.descendant(
                of: session.messageRow(_messageId),
                matching: find.byKey(const ValueKey('message-author-name')),
              ),
              matching: find.byType(Text),
            ),
          )
          .style
          ?.color;

      expect(backdrop(), findsOneWidget);
      expect(authorColor(), _red);

      await session.dispatch('PRESENCE_UPDATE', {
        'status': 'online',
        'activities': <Object?>[],
        'user': {
          'id': SessionHarness.friendId,
          'username': 'friend',
          'collectibles': null,
          'display_name_styles': null,
        },
      });

      expect(backdrop(), findsNothing);
      expect(authorColor(), isNot(_red));
    },
    ready: _ready(),
  );
}
