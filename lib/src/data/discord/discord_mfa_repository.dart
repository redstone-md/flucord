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
      // A code that was mistyped or has already rolled over is refused with
      // a 400. That is the ordinary case: somebody typing six digits against
      // a thirty-second window. Reporting it as an outage would be wrong.
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

  @override
  Future<bool> enableSms() async {
    try {
      await _rest.requestObject('POST', '/users/@me/mfa/sms/enable');
      return true;
    } on DiscordApiException catch (error) {
      // An account with no phone number on it is refused, which is an answer
      // about the account rather than a fault in the client.
      if (error.statusCode == 400 || error.statusCode == 401) return false;
      rethrow;
    }
  }

  @override
  Future<bool> disableSms(String password) async {
    if (password.isEmpty) return false;
    try {
      await _rest.requestObject(
        'POST',
        '/users/@me/mfa/sms/disable',
        body: {'password': password},
      );
      return true;
    } on DiscordApiException catch (error) {
      if (error.statusCode == 400 || error.statusCode == 401) return false;
      rethrow;
    }
  }

  @override
  Future<BackupCodeNonces?> requestBackupCodeChallenge(String password) async {
    if (password.isEmpty) return null;
    try {
      final payload = await _rest.requestObject(
        'POST',
        '/auth/verify/view-backup-codes-challenge',
        body: {'password': password},
      );
      final nonces = BackupCodeNonces(
        view: _string(payload['nonce']) ?? '',
        regenerate: _string(payload['regenerate_nonce']) ?? '',
      );
      return nonces.isEmpty ? null : nonces;
    } on DiscordApiException catch (error) {
      if (error.statusCode == 400 || error.statusCode == 401) return null;
      rethrow;
    }
  }

  @override
  Future<List<String>?> viewBackupCodes({
    required String key,
    required BackupCodeNonces nonces,
    bool regenerate = false,
  }) async {
    final trimmed = key.trim();
    final nonce = nonces.forRequest(regenerating: regenerate);
    if (trimmed.isEmpty || nonce.isEmpty) return null;
    try {
      final payload = await _rest.requestObject(
        'POST',
        '/users/@me/mfa/codes-verification',
        body: {'key': trimmed, 'nonce': nonce, 'regenerate': regenerate},
      );
      return _codes(payload['backup_codes']);
    } on DiscordApiException catch (error) {
      if (error.statusCode == 400 || error.statusCode == 401) return null;
      rethrow;
    }
  }

  @override
  Future<List<SecurityKey>> loadSecurityKeys() async => readSecurityKeys(
    await _rest.getList('/users/@me/mfa/webauthn/credentials'),
  );

  @override
  Future<String?> requestSecurityKeyChallenge(String password) async {
    if (password.isEmpty) return null;
    try {
      final payload = await _rest.requestObject(
        'POST',
        '/users/@me/mfa/webauthn/credentials/registration-options',
        body: {'password': password},
      );
      return _string(payload['challenge']);
    } on DiscordApiException catch (error) {
      // A mistyped password is the ordinary refusal, and reporting it as an
      // outage would tell somebody their client is broken when the answer
      // is about the password they typed.
      if (error.statusCode == 400 || error.statusCode == 401) return null;
      rethrow;
    }
  }

  @override
  Future<bool> registerSecurityKey({
    required String name,
    required String challenge,
    required SecurityKeyRegistration registration,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || challenge.isEmpty) return false;
    try {
      await _rest.requestObject(
        'POST',
        '/users/@me/mfa/webauthn/credentials',
        body: {
          'challenge': challenge,
          'name': trimmed,
          // The browser's registration response, which is the shape
          // Discord's flow was built around.
          'response': {
            'id': registration.credentialId,
            'rawId': registration.credentialId,
            'type': 'public-key',
            'response': {
              'attestationObject': registration.attestationObject,
              'clientDataJSON': registration.clientDataJson,
              'transports': const <String>[],
            },
          },
        },
      );
      return true;
    } on DiscordApiException catch (error) {
      // A proof Discord would not take, or a password that bought the
      // challenge and has since gone stale, is an answer about this key.
      if (error.statusCode == 400 || error.statusCode == 401) return false;
      rethrow;
    }
  }

  @override
  Future<bool> removeSecurityKey(SecurityKey key, String password) async {
    if (password.isEmpty || key.id.isEmpty) return false;
    try {
      await _rest.requestEmpty(
        'DELETE',
        '/users/@me/mfa/webauthn/credentials/${Uri.encodeComponent(key.id)}',
        body: {'password': password},
      );
      return true;
    } on DiscordApiException catch (error) {
      if (error.statusCode == 400 || error.statusCode == 401) return false;
      rethrow;
    }
  }

  /// Reads the key rows. A row without an id names nothing and can be removed
  /// by nothing, so it is dropped rather than shown as a blank.
  static List<SecurityKey> readSecurityKeys(
    List<Map<String, Object?>> payload,
  ) => [
    for (final entry in payload)
      if (_securityKey(entry) case final SecurityKey key) key,
  ];

  static SecurityKey? _securityKey(Map<String, Object?> payload) {
    final id = payload['id'];
    if (id is! String || id.isEmpty) return null;
    return SecurityKey(
      id: id,
      name: _string(payload['name']) ?? 'Security key',
      createdAt: _date(payload['created_at']),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
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
