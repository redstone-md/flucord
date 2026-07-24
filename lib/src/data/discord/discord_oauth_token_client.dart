import 'dart:convert';
import 'dart:io';

import '../../domain/discord_oauth.dart';
import 'discord_rest_client.dart';

typedef DiscordClock = DateTime Function();

final class DiscordOAuthTokenClient {
  DiscordOAuthTokenClient({
    DiscordHttpTransport? transport,
    DelayFunction? delay,
    Uri? baseUri,
    DiscordClock? clock,
  }) : _executor = DiscordHttpExecutor(
         transport: transport,
         delay: delay,
         baseUri: baseUri,
       ),
       _clock = clock ?? DateTime.now;

  static const _userAgent = 'Flucord/0.1.0 (native Flutter client)';

  final DiscordHttpExecutor _executor;
  final DiscordClock _clock;

  Future<DiscordOAuthGrant> exchangeCode({
    required String clientId,
    required String code,
    required Uri redirectUri,
    required String codeVerifier,
  }) async {
    final payload = await _request({
      'client_id': clientId,
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri.toString(),
      'code_verifier': codeVerifier,
    });
    return _grantFrom(payload);
  }

  Future<DiscordOAuthGrant> refresh({
    required String clientId,
    required DiscordOAuthGrant currentGrant,
  }) async {
    final payload = await _request({
      'client_id': clientId,
      'grant_type': 'refresh_token',
      'refresh_token': currentGrant.refreshToken,
    });
    return _grantFrom(
      payload,
      fallbackRefreshToken: currentGrant.refreshToken,
      fallbackScopes: currentGrant.scopes,
    );
  }

  Future<Map<String, Object?>> _request(Map<String, String> fields) async {
    final payload = await _executor.execute(
      'POST',
      '/oauth2/token',
      headers: const {
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
        HttpHeaders.userAgentHeader: _userAgent,
      },
      body: utf8.encode(_formEncode(fields)),
    );
    if (payload is! Map) {
      throw const DiscordOAuthException(
        'Discord returned an invalid OAuth token response.',
      );
    }
    return payload.cast<String, Object?>();
  }

  DiscordOAuthGrant _grantFrom(
    Map<String, Object?> payload, {
    String? fallbackRefreshToken,
    Set<String> fallbackScopes = const {},
  }) {
    final tokenType = payload['token_type'];
    final accessToken = payload['access_token'];
    final refreshToken = payload['refresh_token'] ?? fallbackRefreshToken;
    final expiresIn = payload['expires_in'];
    final rawScope = payload['scope'];
    if (tokenType is! String || tokenType.toLowerCase() != 'bearer') {
      throw const DiscordOAuthException(
        'Discord returned an unsupported OAuth token type.',
      );
    }
    if (accessToken is! String ||
        refreshToken is! String ||
        expiresIn is! num ||
        expiresIn <= 0) {
      throw const DiscordOAuthException(
        'Discord returned an incomplete OAuth token response.',
      );
    }
    final scopes = rawScope is String && rawScope.trim().isNotEmpty
        ? rawScope.split(RegExp(r'\s+'))
        : fallbackScopes;
    return DiscordOAuthGrant(
      accessToken: accessToken,
      refreshToken: refreshToken,
      scopes: scopes,
      expiresAt: _clock().toUtc().add(
        Duration(milliseconds: (expiresIn * 1000).round()),
      ),
    );
  }

  static String _formEncode(Map<String, String> fields) => fields.entries
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}='
            '${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');

  void close() => _executor.close();
}
