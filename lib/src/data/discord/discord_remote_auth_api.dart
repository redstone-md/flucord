import 'dart:convert';
import 'dart:io';

import '../../domain/discord_remote_auth.dart';
import 'discord_desktop_profile.dart';
import 'discord_rest_client.dart';

final class DiscordRemoteAuthApiClient {
  DiscordRemoteAuthApiClient({
    DiscordHttpTransport? transport,
    Uri? baseUri,
    DiscordDesktopClientContext? context,
  }) : _context = context ?? DiscordDesktopClientContext.create(),
       _executor = DiscordHttpExecutor(
         transport: transport,
         baseUri: baseUri ?? Uri.parse('https://discord.com/api/v9'),
       );

  final DiscordDesktopClientContext _context;
  final DiscordHttpExecutor _executor;
  String? _fingerprint;

  Future<String> prepareFingerprint() async {
    final cached = _fingerprint;
    if (cached != null) return cached;
    final payload = await _executor.execute(
      'GET',
      '/experiments',
      headers: _context.unauthenticatedHeaders(),
    );
    if (payload is! Map || payload['fingerprint'] is! String) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Discord fingerprint missing from experiments response',
      );
    }
    final fingerprint = (payload['fingerprint']! as String).trim();
    if (fingerprint.isEmpty) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Discord returned an empty fingerprint',
      );
    }
    return _fingerprint = fingerprint;
  }

  Future<String> exchangeTicket(
    String ticket, {
    String? captchaKey,
    String? captchaRqtoken,
    String? captchaSessionId,
  }) async {
    final fingerprint = await prepareFingerprint();
    final payload = await _executor.execute(
      'POST',
      '/users/@me/remote-auth/login',
      headers: {
        ..._context.unauthenticatedHeaders(fingerprint: fingerprint),
        HttpHeaders.contentTypeHeader: 'application/json',
        'Origin': 'https://discord.com',
        HttpHeaders.refererHeader: 'https://discord.com/login',
        'X-Captcha-Key': ?captchaKey,
        'X-Captcha-Rqtoken': ?captchaRqtoken,
        'X-Captcha-Session-Id': ?captchaSessionId,
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

  DiscordRemoteAuthCaptchaChallenge? captchaChallengeFrom(
    DiscordApiException error,
  ) {
    final payload = error.responsePayload;
    if (payload == null) return null;
    final siteKey = _nonEmptyString(payload['captcha_sitekey']);
    final service = _nonEmptyString(payload['captcha_service']);
    final captchaKey = payload['captcha_key'];
    final required = captchaKey is List && captchaKey.isNotEmpty;
    if (!required || siteKey == null || service == null) return null;
    return DiscordRemoteAuthCaptchaChallenge(
      siteKey: siteKey,
      service: service,
      userAgent: _context.superProperties.browserUserAgent,
      rqData: _nonEmptyString(payload['captcha_rqdata']),
      rqToken: _nonEmptyString(payload['captcha_rqtoken']),
      sessionId: _nonEmptyString(payload['captcha_session_id']),
      serveInvisible: payload['should_serve_invisible'] == true,
    );
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  void close() => _executor.close();
}
