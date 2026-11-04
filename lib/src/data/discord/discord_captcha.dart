import '../../domain/discord_remote_auth.dart';
import 'discord_rest_client.dart';

/// Discord's captcha wire format, shared by sign-in and every other route
/// that can ask for one.
abstract final class DiscordCaptcha {
  /// The captcha Discord asks for in [error], or null when it asked for none.
  ///
  /// [userAgent] is the browser user agent the captcha view must present.
  static DiscordRemoteAuthCaptchaChallenge? challengeOf(
    DiscordApiException error, {
    required String userAgent,
  }) {
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
      userAgent: userAgent,
      rqData: _nonEmptyString(payload['captcha_rqdata']),
      rqToken: _nonEmptyString(payload['captcha_rqtoken']),
      sessionId: _nonEmptyString(payload['captcha_session_id']),
      serveInvisible: payload['should_serve_invisible'] == true,
    );
  }

  /// The headers that carry [answer] on the retried request.
  static Map<String, String> headersOf(DiscordCaptchaAnswer answer) => {
    'X-Captcha-Key': answer.key,
    'X-Captcha-Rqtoken': ?answer.challenge.rqToken,
    'X-Captcha-Session-Id': ?answer.challenge.sessionId,
  };

  static String? _nonEmptyString(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
