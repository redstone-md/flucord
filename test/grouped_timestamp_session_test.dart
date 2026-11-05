import 'package:flucord/src/data/discord/discord_user_settings_proto.dart';
import 'package:flucord/src/data/proto/proto_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_font.dart';
import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

/// The clock beside a grouped message fits its gutter on one line, in the
/// bundled font, even at its widest: `12:59 PM` on the 12-hour clock.
void main() {
  const hour12OnWire = 1;

  String sentAt(int hour, int minute) =>
      DateTime(2026, 7, 25, hour, minute).toUtc().toIso8601String();

  Map<String, Object?> fromFriend(String id, String time) => rawMessage(
    id: id,
    channelId: SessionHarness.channelId,
    guildId: SessionHarness.guildId,
    authorId: SessionHarness.friendId,
    content: 'Hello',
    timestamp: time,
  );

  testSession(
    'a grouped timestamp fits on one line',
    (tester, session) async {
      await loadAppFont(tester);
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch(
        'MESSAGE_CREATE',
        fromFriend('400000000000000001', sentAt(12, 58)),
      );
      await session.dispatch(
        'MESSAGE_CREATE',
        fromFriend('400000000000000002', sentAt(12, 59)),
      );

      // Selectable text sits under a mouse region, so the paragraph is found
      // inside it.
      final clock = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text('12:59 PM'),
          matching: find.byType(RichText),
        ),
      );
      // Room for the whole clock on one line means it does not wrap.
      expect(
        clock.size.width,
        greaterThanOrEqualTo(clock.getMaxIntrinsicWidth(double.infinity)),
      );
      expect(clock.didExceedMaxLines, isFalse);
    },
    ready: SessionHarness.defaultReady()
      ..['user_settings_proto'] = DiscordUserSettingsProto.encodeBase64(
        (ProtoMessage()..setMessage(
              PreloadedUserSettingsField.appearance,
              ProtoMessage()
                ..setVarint(AppearanceField.timestampHourCycle, hour12OnWire),
            ))
            .encode(),
      ),
  );
}
