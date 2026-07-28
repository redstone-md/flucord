import 'dart:convert';

import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flutter_test/flutter_test.dart';

const _guild = '111111111111111111';
const _channel = '222222222222222222';
const _message = '333333333333333333';

void main() {
  test('every action carries the code the bundle names', () {
    expect(AutoModAlertAction.setCompleted.code, 1);
    expect(AutoModAlertAction.unsetCompleted.code, 2);
    expect(AutoModAlertAction.deleteUserMessage.code, 3);
    expect(AutoModAlertAction.submitFeedback.code, 4);
  });

  test('the request names the alert, not the message that tripped', () async {
    final transport = _Transport();
    final client = _client(transport);

    await client.resolveAutoModAlert(
      guildId: _guild,
      channelId: _channel,
      messageId: _message,
      actionType: AutoModAlertAction.deleteUserMessage.code,
    );

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(
      request.uri.path,
      endsWith('/guilds/$_guild/auto-moderation/alert-action'),
    );
    // Discord resolves the offending message from the alert itself, so only
    // the alert is named; sending the offence would be sending the wrong id.
    expect(request.body, {
      'message_id': _message,
      'channel_id': _channel,
      'alert_action_type': 3,
    });
  });

  test('each action reaches the route unchanged', () async {
    for (final action in AutoModAlertAction.values) {
      final transport = _Transport();
      final client = _client(transport);

      await client.resolveAutoModAlert(
        guildId: _guild,
        channelId: _channel,
        messageId: _message,
        actionType: action.code,
      );

      expect(
        transport.requests.single.body?['alert_action_type'],
        action.code,
        reason: action.name,
      );
    }
  });
}

DiscordDesktopApiClient _client(_Transport transport) =>
    DiscordDesktopApiClient(
      authorization: 'token',
      headers: const {},
      transport: transport,
      baseUri: Uri.parse('https://discord.com/api/v9'),
    );

final class _Recorded {
  const _Recorded({required this.method, required this.uri, this.body});

  final String method;
  final Uri uri;
  final Map<String, Object?>? body;
}

final class _Transport implements DiscordHttpTransport {
  final List<_Recorded> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    final decoded = body == null
        ? null
        : jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    requests.add(_Recorded(method: method, uri: uri, body: decoded));
    return const DiscordHttpResponse(statusCode: 204, headers: {}, body: '');
  }

  @override
  void close() {}
}
