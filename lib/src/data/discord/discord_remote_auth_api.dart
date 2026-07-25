import 'dart:convert';
import 'dart:io';

import 'discord_rest_client.dart';

final class DiscordRemoteAuthApiClient {
  DiscordRemoteAuthApiClient({DiscordHttpTransport? transport, Uri? baseUri})
    : _executor = DiscordHttpExecutor(
        transport: transport,
        baseUri: baseUri ?? Uri.parse('https://discord.com/api/v9'),
      );

  final DiscordHttpExecutor _executor;

  Future<String> exchangeTicket(String ticket) async {
    final payload = await _executor.execute(
      'POST',
      '/users/@me/remote-auth/login',
      headers: const {
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.contentTypeHeader: 'application/json',
        'Origin': 'https://discord.com',
      },
      body: utf8.encode(jsonEncode({'ticket': ticket})),
    );
    if (payload is! Map || payload['encrypted_token'] is! String) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Remote auth token missing from response',
      );
    }
    return payload['encrypted_token']! as String;
  }

  void close() => _executor.close();
}
