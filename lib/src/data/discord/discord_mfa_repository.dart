import '../../domain/multi_factor_auth.dart';
import 'discord_rest_client.dart';

/// Two-factor authentication, over the desktop-user session.
///
/// The secret never leaves the client until a code minted from it works, so
/// Discord is only ever told about a secret the account has already proved it
/// can use.
final class DiscordMfaRepository implements MultiFactorAuthRepository {
  DiscordMfaRepository(this._rest);

  final DiscordRestClient _rest;

  @override
  Future<MfaEnrolment?> enableTotp({
    required TotpSecret secret,
    required String code,
  }) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty || secret.value.isEmpty) return null;
    try {
      final payload = await _rest.requestObject(
        'POST',
        '/users/@me/mfa/totp/enable',
        body: {'code': trimmed, 'secret': secret.value},
      );
      return MfaEnrolment(
        token: _string(payload['token']) ?? '',
        backupCodes: _codes(payload['backup_codes']),
      );
    } on DiscordApiException catch (error) {
      // A code that was mistyped or has already rolled over is refused with a
      // 400. That is the ordinary case — somebody typing six digits against a
      // thirty-second window — and reporting it as an outage would be wrong.
      if (error.statusCode == 400 || error.statusCode == 401) return null;
      rethrow;
    }
  }

  @override
  Future<bool> disableTotp(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return false;
    try {
      await _rest.requestObject(
        'POST',
        '/users/@me/mfa/totp/disable',
        body: {'code': trimmed},
      );
      return true;
    } on DiscordApiException catch (error) {
      if (error.statusCode == 400 || error.statusCode == 401) return false;
      rethrow;
    }
  }

  /// Backup codes arrive as objects carrying the code and whether it is spent;
  /// a spent one is dropped, because offering it would be offering a code that
  /// no longer opens anything.
  static List<String> _codes(Object? value) {
    if (value is! List) return const [];
    return [
      for (final raw in value)
        if (raw is String)
          raw
        else if (raw is Map && raw['consumed'] != true)
          if (_string(raw['code']) case final String code) code,
    ];
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }
}
