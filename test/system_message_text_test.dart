import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/system_message_text.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('describes authored system messages with normalized detail', () {
    final message = _message(
      DiscordMessageType.threadCreated,
      body: '  release\n  checklist  ',
    );

    expect(
      SystemMessageText.describe(message, 'Jack'),
      'Jack started a thread: release checklist',
    );
  });

  test('describes server-wide incidents without inventing an author', () {
    final message = _message(DiscordMessageType.guildIncidentReportRaid);

    expect(
      SystemMessageText.describe(message, 'Jack'),
      'A raid was reported in this server.',
    );
  });

  test('uses a stable fallback for unsupported timeline rows', () {
    final message = _message(DiscordMessageType.unknown);

    expect(SystemMessageText.describe(message, 'Jack'), 'Server event');
  });
}

ChatMessage _message(DiscordMessageType type, {String body = ''}) =>
    ChatMessage(
      id: 'message-1',
      channelId: 'channel-1',
      authorId: 'member-1',
      body: body,
      sentAt: DateTime(2026, 7, 24, 8),
      type: type,
    );
