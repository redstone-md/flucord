import 'dart:math' as math;

import 'package:flucord/src/presentation/widgets/member_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _openerId = '900000000000000011';
const _followUpId = '900000000000000012';
const _mentionId = '900000000000000013';

const _openerBody = 'the first line of a new author';
const _followUpBody = 'a second line from the same author';
const _mentionBody = 'a line that names you';

/// The highlight that wraps one message: hover and mention fill it.
Finder _surface(String id) => find.byKey(ValueKey('message-surface-$id'));

Finder _in(SessionHarness session, String id, Finder matching) =>
    find.descendant(of: session.messageRow(id), matching: matching);

Rect _bodyOf(
  WidgetTester tester,
  SessionHarness session,
  String id,
  String b,
) => tester.getRect(
  _in(session, id, find.textContaining(b, findRichText: true)).first,
);

/// A new author, a follow-up from them, and, after a pause, a message from
/// them that mentions the reader.
Future<void> _openThreeRows(SessionHarness session) async {
  await session.openChannel(SessionHarness.channelId);
  for (final (id, body, time, mentions) in [
    (_openerId, _openerBody, '2026-07-25T10:00:00+00:00', false),
    (_followUpId, _followUpBody, '2026-07-25T10:01:00+00:00', false),
    (_mentionId, _mentionBody, '2026-07-25T10:30:00+00:00', true),
  ]) {
    await session.dispatch('MESSAGE_CREATE', {
      ...rawMessage(
        id: id,
        channelId: SessionHarness.channelId,
        guildId: SessionHarness.guildId,
        authorId: SessionHarness.friendId,
        content: body,
        timestamp: time,
      ),
      if (mentions)
        'mentions': [
          {'id': SessionHarness.currentUserId, 'username': 'me'},
        ],
    });
  }
}

void main() {
  testSession('a new author opens a group 10 px below the last message', (
    tester,
    session,
  ) async {
    await _openThreeRows(session);

    final row = tester.getRect(session.messageRow(_openerId));
    final surface = tester.getRect(_surface(_openerId));

    expect(surface.top - row.top, 10);
    expect(surface.bottom, row.bottom);
  });

  testSession('a follow-up has no group margin', (tester, session) async {
    await _openThreeRows(session);

    final row = tester.getRect(session.messageRow(_followUpId));
    final surface = tester.getRect(_surface(_followUpId));

    expect(surface, row);
  });

  testSession('the avatar is 40 px, 16 px in, its top on the name row', (
    tester,
    session,
  ) async {
    await _openThreeRows(session);

    final surface = tester.getRect(_surface(_openerId));
    final avatar = tester.getRect(
      _in(session, _openerId, find.byType(MemberAvatar)),
    );
    final name = tester.getRect(
      _in(session, _openerId, find.text('user-${SessionHarness.friendId}')),
    );

    expect(avatar.size, const Size.square(40));
    expect(avatar.left - surface.left, 16);
    expect(name.left - avatar.right, 12);
    expect(name.top, avatar.top);
    expect(name.height, 18);
  });

  // Each pair is the space above and below the content inside the surface.
  // The owner asked for these to match, so the hover fill wraps evenly.
  testSession('the surface pads its content evenly above and below', (
    tester,
    session,
  ) async {
    await _openThreeRows(session);

    (double, double) padding(String id, String body, {bool avatar = true}) {
      final surface = tester.getRect(_surface(id));
      final text = _bodyOf(tester, session, id, body);
      final content = avatar
          ? tester.getRect(_in(session, id, find.byType(MemberAvatar)))
          : text;
      final bottom = math.max(content.bottom, text.bottom);
      return (content.top - surface.top, surface.bottom - bottom);
    }

    expect(padding(_openerId, _openerBody), (4, 4));
    expect(padding(_followUpId, _followUpBody, avatar: false), (1, 1));
    expect(padding(_mentionId, _mentionBody), (7, 7));
  });

  testSession('the date lives in the divider, not on the row', (
    tester,
    session,
  ) async {
    const nextDayId = '900000000000000014';
    await _openThreeRows(session);
    await session.dispatch(
      'MESSAGE_CREATE',
      rawMessage(
        id: nextDayId,
        channelId: SessionHarness.channelId,
        guildId: SessionHarness.guildId,
        authorId: SessionHarness.friendId,
        content: 'the next morning',
        timestamp: '2026-07-26T12:00:00+00:00',
      ),
    );

    final year = find.textContaining('2026');
    expect(_in(session, nextDayId, year), findsNothing);
    final date = tester.widget<Text>(year).style!;
    expect(date.fontSize, 12);
    expect(date.fontWeight, FontWeight.w400);
  });

  testSession('body text sits on a 21 px line', (tester, session) async {
    await _openThreeRows(session);

    final body = _bodyOf(tester, session, _followUpId, _followUpBody);

    expect(body.height, 21);
  });
}
