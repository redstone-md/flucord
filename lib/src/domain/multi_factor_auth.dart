import 'dart:math';

/// A one-time-password secret, as an authenticator app wants it.
///
/// The secret is generated here rather than asked for: Discord's own client
/// mints it locally and sends it up only alongside the first working code,
/// which means the server never sees a secret the account did not prove it
/// could use.
final class TotpSecret {
  const TotpSecret(this.value);

  /// Twenty random bytes, base32 with no padding. Discord's own length.
  factory TotpSecret.generate({Random? random}) {
    // Random.secure() rather than Random(): this is a credential, and a
    // predictable one would let anybody who knew the seed mint the codes.
    final source = random ?? Random.secure();
    final bytes = [for (var i = 0; i < 20; i++) source.nextInt(256)];
    return TotpSecret(_base32(bytes));
  }

  /// Upper case, no separators. What goes on the wire.
  final String value;

  /// Grouped in fours and lower-cased, which is how a secret is read aloud
  /// and typed into an authenticator by hand.
  String get readable {
    final lower = value.toLowerCase();
    final groups = <String>[];
    for (var index = 0; index < lower.length; index += 4) {
      groups.add(lower.substring(index, (index + 4).clamp(0, lower.length)));
    }
    return groups.join(' ');
  }

  /// The URI an authenticator app scans.
  String provisioningUri({required String account, String issuer = 'Discord'}) {
    final label =
        '${Uri.encodeComponent(issuer)}:${Uri.encodeComponent(account)}';
    return 'otpauth://totp/$label?secret=$value&issuer=${Uri.encodeComponent(issuer)}';
  }

  /// Reads a secret somebody typed or pasted back, however they spaced it.
  static TotpSecret parse(String input) =>
      TotpSecret(input.replaceAll(RegExp(r'[\s._-]+'), '').toUpperCase());

  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static String _base32(List<int> bytes) {
    final buffer = StringBuffer();
    var bits = 0;
    var value = 0;
    for (final byte in bytes) {
      value = (value << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        buffer.write(_alphabet[(value >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) buffer.write(_alphabet[(value << (5 - bits)) & 31]);
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) => other is TotpSecret && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// What Discord answers when two-factor authentication is switched on.
final class MfaEnrolment {
  const MfaEnrolment({this.token = '', this.backupCodes = const []});

  /// The session token Discord reissues, since enabling MFA invalidates the
  /// old one. Never logged and never shown.
  final String token;

  /// The codes that get somebody back in when the authenticator is lost.
  final List<String> backupCodes;

  bool get hasBackupCodes => backupCodes.isNotEmpty;
}

/// Turns two-factor authentication on and off.
abstract interface class MultiFactorAuthRepository {
  /// `POST /users/@me/mfa/totp/enable`, with the first working code.
  ///
  /// Returns null when Discord refused the code — a mistyped or expired one,
  /// which is the ordinary case and not a failure.
  Future<MfaEnrolment?> enableTotp({
    required TotpSecret secret,
    required String code,
  });

  /// `POST /users/@me/mfa/totp/disable`, with a current code.
  Future<bool> disableTotp(String code);
}

/// Base32 without padding, as `TotpSecret` writes it. Exposed for the tests
/// that check a generated secret decodes back to twenty bytes.
List<int> decodeBase32(String value) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final bytes = <int>[];
  var bits = 0;
  var buffer = 0;
  for (final character in value.toUpperCase().split('')) {
    final index = alphabet.indexOf(character);
    if (index < 0) continue;
    buffer = (buffer << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bytes.add((buffer >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return bytes;
}
