import '../../domain/account_standing.dart';
import 'discord_rest_client.dart';

/// The safety hub, over the desktop-user session.
///
/// Read-only but for one write, and that write is a request rather than a
/// change: asking Discord to look at a record again. Nothing here can alter
/// what is on the account's record, which is why there is no patch.
final class DiscordSafetyHubRepository implements SafetyHubRepository {
  DiscordSafetyHubRepository(this._rest);

  final DiscordRestClient _rest;

  @override
  Future<AccountStanding> loadAccountStanding() async =>
      readStanding(await _rest.getObject('/safety-hub/@me'));

  @override
  Future<bool> requestReview(String classificationId) async {
    if (classificationId.isEmpty) return false;
    try {
      await _rest.requestEmpty(
        'POST',
        '/safety-hub/request-review/'
            '${Uri.encodeComponent(classificationId)}',
      );
      return true;
    } on DiscordApiException catch (error) {
      // A record already appealed, or one Discord will not reopen, answers
      // with a refusal rather than an outage. Reporting that as a failure
      // would read as "the client broke" for a perfectly ordinary no.
      if (error.statusCode == 400 || error.statusCode == 409) return false;
      rethrow;
    }
  }

  @override
  Future<AccountSuspension> loadSuspension() async {
    try {
      return readSuspension(await _rest.getObject('/safety-hub/suspended/@me'));
    } on DiscordApiException catch (error) {
      // 404 is Discord saying the account is not suspended, which is an
      // answer rather than a fault; 403 is the same for a session that may
      // not ask.
      if (error.statusCode == 404 || error.statusCode == 403) {
        return AccountSuspension.none;
      }
      rethrow;
    }
  }

  @override
  Future<bool> requestSuspendedReview(String classificationId) async {
    if (classificationId.isEmpty) return false;
    try {
      await _rest.requestEmpty(
        'POST',
        '/safety-hub/suspended/request-review/'
            '${Uri.encodeComponent(classificationId)}',
      );
      return true;
    } on DiscordApiException catch (error) {
      if (error.statusCode == 400 || error.statusCode == 409) return false;
      rethrow;
    }
  }

  /// Reads the suspended payload.
  ///
  /// Every field is optional on the wire, and an account really can be
  /// suspended with nothing said about when it ends.
  static AccountSuspension readSuspension(Map<String, Object?> payload) {
    final ends = payload['ends_at'] ?? payload['expires_at'];
    return AccountSuspension(
      isSuspended:
          payload['suspended'] == true || payload['is_suspended'] == true,
      reason: _string(payload['reason']) ?? _string(payload['title']) ?? '',
      classificationId:
          _string(payload['classification_id']) ?? _string(payload['id']),
      canRequestReview:
          payload['can_request_review'] == true ||
          payload['appeal_eligible'] == true,
      endsAt: ends is String ? DateTime.tryParse(ends)?.toUtc() : null,
    );
  }

  /// Reads the safety-hub payload.
  ///
  /// The two classification lists are folded into one, with the guild ones
  /// keeping their guild, because the surface shows them as one record each
  /// either way and the split is only in how Discord fetches them.
  static AccountStanding readStanding(Map<String, Object?> payload) {
    final appealable = {
      for (final raw in _list(payload['appeal_eligibility']))
        if (_string(raw) case final String id) id,
    };
    return AccountStanding(
      username: _string(payload['username']) ?? '',
      standing: _int(payload['account_standing']) ?? 0,
      isDsaEligible: payload['is_dsa_eligible'] == true,
      isAppealEligible: payload['is_appeal_eligible'] == true,
      classifications: [
        for (final raw in _list(payload['classifications']))
          ?_classification(raw, appealable: appealable),
        for (final raw in _list(payload['guild_classifications']))
          ?_classification(raw, appealable: appealable, requireGuild: true),
      ],
    );
  }

  static AccountClassification? _classification(
    Object? raw, {
    required Set<String> appealable,
    bool requireGuild = false,
  }) {
    if (raw is! Map) return null;
    final payload = raw.cast<String, Object?>();
    final id = _string(payload['id']);
    if (id == null) return null;
    final guildId = _string(payload['guild_id']) ?? '';
    // A guild record with no guild is a record about the account that arrived
    // in the wrong list; keeping it in the guild half would file it under a
    // server that is not named.
    if (requireGuild && guildId.isEmpty) return null;
    return AccountClassification(
      id: id,
      title: _string(payload['title']) ?? '',
      subtitle: _string(payload['subtitle']) ?? '',
      guildId: guildId,
      appealEligible:
          appealable.contains(id) || payload['is_appeal_eligible'] == true,
    );
  }

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static String? _string(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }

  static int? _int(Object? value) => switch (value) {
    final int raw => raw,
    final String raw => int.tryParse(raw),
    _ => null,
  };
}
