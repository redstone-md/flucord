import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('sends the exact documented forwarding reference', () async {
    final transport = _RecordingTransport();
    final client = DiscordApiClient(botToken: 'token', transport: transport);

    await client.forwardMessage(
      sourceChannelId: 'source channel',
      sourceMessageId: 'source-message',
      targetChannelId: 'target-channel',
    );

    expect(transport.method, 'POST');
    expect(transport.uri.path, '/api/v10/channels/target-channel/messages');
    final payload = jsonDecode(utf8.decode(transport.body!)) as Map;
    expect(payload.keys, ['message_reference']);
    expect(payload['message_reference'], {
      'type': 1,
      'message_id': 'source-message',
      'channel_id': 'source channel',
    });
  });

  test('accepts only Discord-supported source message shapes', () {
    ChatMessage message(DiscordMessageType type, {MessagePoll? poll}) =>
        ChatMessage(
          id: 'message-1',
          channelId: 'channel-1',
          authorId: 'user-1',
          body: 'Body',
          sentAt: DateTime(2026, 7, 24),
          type: type,
          poll: poll,
        );

    expect(message(DiscordMessageType.defaultMessage).canForward, isTrue);
    expect(message(DiscordMessageType.reply).canForward, isTrue);
    expect(message(DiscordMessageType.chatInputCommand).canForward, isTrue);
    expect(message(DiscordMessageType.contextMenuCommand).canForward, isTrue);
    expect(message(DiscordMessageType.call).canForward, isFalse);
  });
}

final class _RecordingTransport implements DiscordHttpTransport {
  late String method;
  late Uri uri;
  List<int>? body;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    this.method = method;
    this.uri = uri;
    this.body = body;
    return const DiscordHttpResponse(statusCode: 200, headers: {}, body: '{}');
  }

  @override
  void close() {}
}
