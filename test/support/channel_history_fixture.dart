import 'fake_discord_wire.dart';
import 'session_harness.dart';

/// A numbered message history in the harness's guild channel. Index 0 is the
/// oldest message, and a larger index is always a newer id and a later time.
abstract final class ChannelHistoryFixture {
  static const messagesPath =
      '/api/v9/channels/${SessionHarness.channelId}/messages';

  static String idOf(int index) => '9${index.toString().padLeft(17, '0')}';

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

  /// A page of history as Discord answers it, newest first.
  static List<Map<String, Object?>> page(int first, int count) => [
    for (var index = first + count - 1; index >= first; index--) message(index),
  ];
}
