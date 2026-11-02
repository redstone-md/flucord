import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/discord_snowflake.dart';

import 'fake_discord_wire.dart';
import 'session_harness.dart';

/// A numbered message history in the harness's guild channel. Index 0 is the
/// oldest message, and a larger index is always a newer id and a later time.
abstract final class ChannelHistoryFixture {
  static const messagesPath =
      '/api/v9/channels/${SessionHarness.channelId}/messages';

  static final _idsStartAt = DateTime.now()
      .subtract(const Duration(days: 2))
      .millisecondsSinceEpoch;

  /// An id from recent days, because the app deletes a read cursor older than
  /// 30.
  static String idOf(int index) => DiscordSnowflake.fromTimestampMillis(
    _idsStartAt + index * Duration.millisecondsPerMinute,
  );

  /// The index [idOf] made this id from.
  static int indexOf(String id) =>
      (DiscordSnowflake.timestampMillis(id) - _idsStartAt) ~/
      Duration.millisecondsPerMinute;

  static Map<String, Object?> message(
    int index, {
    String? authorId,
    String? content,
  }) => rawMessage(
    id: idOf(index),
    channelId: SessionHarness.channelId,
    guildId: SessionHarness.guildId,
    authorId: authorId ?? SessionHarness.friendId,
    content: content ?? 'Message $index',
    timestamp: DateTime.utc(
      2026,
      7,
      20,
    ).add(Duration(minutes: index * 10)).toIso8601String(),
  );

  /// READY for an account that has read the channel up to [firstUnread], with
  /// the channel's newest message at [newest].
  static Map<String, Object?> readyWithUnread({
    required int firstUnread,
    required int newest,
  }) => SessionHarness.defaultReady()
    ..['guilds'] = [
      rawGuild(
        id: SessionHarness.guildId,
        name: 'The Forge',
        channels: [
          rawChannel(
            id: SessionHarness.channelId,
            name: 'general',
            lastMessageId: idOf(newest),
          ),
        ],
        everyonePermissions: '${DiscordPermissions.viewChannel}',
      ),
    ]
    ..['read_state'] = {
      'version': 1,
      'partial': false,
      'entries': [
        {
          'id': SessionHarness.channelId,
          'last_message_id': idOf(firstUnread - 1),
        },
      ],
    };

  /// A page of history as Discord answers it, newest first.
  static List<Map<String, Object?>> page(int first, int count) => [
    for (var index = first + count - 1; index >= first; index--) message(index),
  ];
}
