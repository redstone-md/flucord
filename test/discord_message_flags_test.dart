import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/discord/discord_message_nonce_factory.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('maps raw message flags and preserves them on partial updates', () {
    final mapper = DiscordMapper();
    final original = mapper.message({
      'id': 'message-1',
      'channel_id': 'channel-1',
      'author': {'id': 'bot-1'},
      'content': 'Quiet release',
      'timestamp': '2026-07-24T08:00:00Z',
      'flags':
          DiscordMessageFlag.suppressEmbeds.bit |
          DiscordMessageFlag.suppressNotifications.bit |
          (1 << 30),
    });

    expect(original.suppressesEmbeds, isTrue);
    expect(original.suppressesNotifications, isTrue);
    expect(original.flags & (1 << 30), isNot(0));

    final partial = mapper.message({
      'id': 'message-1',
      'channel_id': 'channel-1',
      'edited_timestamp': null,
    }, fallback: original);
    expect(partial.flags, original.flags);

    final cleared = mapper.message({
      'id': 'message-1',
      'channel_id': 'channel-1',
      'flags': 0,
    }, fallback: original);
    expect(cleared.flags, 0);
  });

  test(
    'sends enforced nonce and silent flag in the exact JSON payload',
    () async {
      final transport = _RecordingTransport();
      final client = DiscordApiClient(botToken: 'token', transport: transport);

      await client.createMessage(
        channelId: 'channel-1',
        content: 'Quiet release',
        nonce: 'native-message-1',
        enforceNonce: true,
        suppressNotifications: true,
      );

      final request = transport.requests.single;
      expect(request.method, 'POST');
      final payload = jsonDecode(utf8.decode(request.body!)) as Map;
      expect(payload['content'], 'Quiet release');
      expect(payload['nonce'], 'native-message-1');
      expect(payload['enforce_nonce'], isTrue);
      expect(payload['flags'], DiscordMessageFlag.suppressNotifications.bit);
    },
  );

  test('edits only the documented suppress-embed flag', () async {
    final transport = _RecordingTransport();
    final client = DiscordApiClient(botToken: 'token', transport: transport);

    await client.editMessageFlags(
      channelId: 'channel-1',
      messageId: 'message-1',
      suppressEmbeds: true,
    );

    final request = transport.requests.single;
    expect(request.method, 'PATCH');
    expect(request.uri.path, '/api/v10/channels/channel-1/messages/message-1');
    final payload = jsonDecode(utf8.decode(request.body!)) as Map;
    expect(payload, {'flags': DiscordMessageFlag.suppressEmbeds.bit});
  });

  test(
    'nonce factory stays unique, deterministic, and within Discord limit',
    () {
      final factory = DiscordMessageNonceFactory(
        clock: () => DateTime.utc(2026, 7, 24, 8),
      );

      final first = factory.next();
      final second = factory.next();

      expect(first, isNot(second));
      expect(first.length, lessThanOrEqualTo(25));
      expect(second.length, lessThanOrEqualTo(25));
    },
  );

  test('rejects nonces beyond the documented 25 character limit', () {
    final client = DiscordApiClient(
      botToken: 'token',
      transport: _RecordingTransport(),
    );

    expect(
      () => client.createMessage(
        channelId: 'channel-1',
        content: 'Body',
        nonce: 'xxxxxxxxxxxxxxxxxxxxxxxxxx',
      ),
      throwsArgumentError,
    );
  });
}

final class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.uri,
    required this.body,
  });

  final String method;
  final Uri uri;
  final List<int>? body;
}

final class _RecordingTransport implements DiscordHttpTransport {
  final List<_RecordedRequest> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(_RecordedRequest(method: method, uri: uri, body: body));
    return const DiscordHttpResponse(statusCode: 200, headers: {}, body: '{}');
  }

  @override
  void close() {}
}
