import '../../domain/family_centre.dart';
import 'discord_rest_client.dart';

/// The family centre, over the desktop-user session.
final class DiscordFamilyCentreRepository implements FamilyCentreRepository {
  DiscordFamilyCentreRepository(this._rest);

  final DiscordRestClient _rest;

  @override
  Future<FamilyCentre> loadFamilyCentre() async =>
      readFamilyCentre(await _rest.getObject('/family-center/@me'));

  @override
  Future<TeenControls> loadTeenControls(String teenId) async {
    if (teenId.isEmpty) return const TeenControls();
    try {
      return readTeenControls(
        teenId,
        await _rest.getObject(
          '/family-center/${Uri.encodeComponent(teenId)}/settings-and-consents',
        ),
      );
    } on DiscordApiException catch (error) {
      // A teen can unlink at any moment, and a parent reading a link that has
      // gone gets a refusal rather than an outage.
      if (error.statusCode == 403 || error.statusCode == 404) {
        return TeenControls(userId: teenId);
      }
      rethrow;
    }
  }

  /// Reads the settings-and-consents payload.
  ///
  /// Both halves are flat maps of name to flag on the wire, and both are kept
  /// as they arrived: these are controls over somebody else's account, and a
  /// client that renamed one would tell a parent they had set something other
  /// than what they set.
  static TeenControls readTeenControls(
    String teenId,
    Map<String, Object?> payload,
  ) => TeenControls(
    userId: teenId,
    settings: _flags(payload['settings']),
    consents: _flags(payload['consents']),
  );

  static Map<String, bool> _flags(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.value is bool) '${entry.key}': entry.value! as bool,
    };
  }

  @override
  Future<String?> requestLinkCode() async {
    try {
      final payload = await _rest.requestObject(
        'POST',
        '/family-center/@me/link-code',
      );
      return _string(payload['code']) ?? _string(payload['link_code']);
    } on DiscordApiException catch (error) {
      // An account Discord will not issue a code for answers with a refusal.
      // Treating that as an outage would tell somebody their client is broken
      // when the truth is that their account is not eligible.
      if (error.statusCode == 400 || error.statusCode == 403) return null;
      rethrow;
    }
  }

  /// Reads the family-centre payload.
  static FamilyCentre readFamilyCentre(Map<String, Object?> payload) {
    final auditLog = payload['teen_audit_log'];
    return FamilyCentre(
      ageGroup: _string(payload['age_group']) ?? '',
      linkedUserIds: [
        for (final raw in _list(payload['linked_users']))
          if (raw is Map)
            if (_string(raw['user_id']) case final String id) id,
      ],
      userNames: _names(payload['users']),
      activity: auditLog is Map
          ? _activity(auditLog.cast<String, Object?>())
          : null,
    );
  }

  static TeenActivitySummary? _activity(Map<String, Object?> payload) {
    final summary = TeenActivitySummary(
      teenUserId: _string(payload['teen_user_id']) ?? '',
      totals: {
        for (final entry in _map(payload['totals']).entries)
          if (_int(entry.value) case final int count) entry.key: count,
      },
      userIds: _ids(payload['users']),
      guildIds: _ids(payload['guilds']),
    );
    // A summary about nobody, with nothing counted, is what Discord sends
    // before a teenager has been linked. Showing an empty card would suggest
    // the link exists and did nothing.
    return summary.isEmpty && summary.teenUserId.isEmpty ? null : summary;
  }

  /// Ids from a list that may hold either bare ids or objects naming one.
  static List<String> _ids(Object? value) => [
    for (final raw in _list(value))
      if (_entryId(raw) case final String id) id,
  ];

  static String? _entryId(Object? raw) {
    if (raw is String) return raw.isEmpty ? null : raw;
    if (raw is! Map) return null;
    return _string(raw['id']) ??
        _string(raw['user_id']) ??
        _string(raw['guild_id']);
  }

  static Map<String, String> _names(Object? value) {
    final names = <String, String>{};
    for (final raw in _list(value)) {
      if (raw is! Map) continue;
      final id = _string(raw['id']) ?? _string(raw['user_id']);
      if (id == null) continue;
      final name =
          _string(raw['global_name']) ??
          _string(raw['display_name']) ??
          _string(raw['username']);
      if (name != null) names[id] = name;
    }
    return Map.unmodifiable(names);
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : const {};

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
