import '../../domain/age_verification.dart';
import 'discord_rest_client.dart';

/// Age verification, over the desktop-user session.
///
/// Reads what Discord offers and starts the chosen one. No document, photo or
/// wallet credential passes through here: those go from the person to the
/// vendor, on the vendor's own surface.
final class DiscordAgeVerificationRepository
    implements AgeVerificationRepository {
  DiscordAgeVerificationRepository(this._rest);

  final DiscordRestClient _rest;

  @override
  Future<List<AgeVerificationMethod>> loadMethods() async =>
      readMethods(await _rest.getObject('/age-verification/methods'));

  @override
  Future<AgeVerificationStart?> start(AgeVerificationMethod method) async {
    if (method.method.isEmpty) return null;
    try {
      final payload = await _rest.requestObject(
        'POST',
        '/age-verification/verify',
        body: {'method': method.method, 'vendor': method.vendor},
      );
      return AgeVerificationStart(
        // Discord names the field differently per vendor; both spellings seen
        // in the bundle are read, and anything else leaves the start with no
        // link rather than with a guess.
        continueUrl:
            _string(payload['url']) ?? _string(payload['redirect_url']) ?? '',
      );
    } on DiscordApiException catch (error) {
      // An account that may not use this method is refused. That is an answer
      // about eligibility, not a fault in the client.
      if (error.statusCode == 400 || error.statusCode == 403) return null;
      rethrow;
    }
  }

  /// Reads the method list.
  static List<AgeVerificationMethod> readMethods(Map<String, Object?> payload) {
    final methods = payload['methods'];
    if (methods is! List) return const [];
    return [
      for (final raw in methods)
        if (raw is Map) ?_method(raw.cast<String, Object?>()),
    ];
  }

  static AgeVerificationMethod? _method(Map<String, Object?> payload) {
    final method = _string(payload['method']) ?? _string(payload['type']);
    if (method == null) return null;
    return AgeVerificationMethod(
      method: method,
      vendor: _string(payload['vendor']) ?? '',
      title: _string(payload['title']) ?? '',
      description: _string(payload['description']) ?? '',
      providedBy: _string(payload['provided_by']) ?? '',
    );
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }
}
