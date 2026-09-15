import '../../domain/account_data_package.dart';
import 'discord_rest_client.dart';

/// The account's data package, over the desktop-user session.
///
/// Nothing is downloaded here and no link is opened: the route starts a
/// collection on Discord's side and reports where it stands, and the archive
/// itself arrives by email, between the person and Discord.
final class DiscordAccountDataPackageRepository
    implements AccountDataPackageRepository {
  DiscordAccountDataPackageRepository(this._rest);

  final DiscordRestClient _rest;

  @override
  Future<AccountDataPackage?> loadLatest() async =>
      readPayload(await _rest.request('GET', '/users/@me/harvest/latest'));

  @override
  Future<AccountDataPackage?> request() async {
    try {
      return readPayload(await _rest.request('POST', '/users/@me/harvest'));
    } on DiscordApiException catch (error) {
      // An account without a verified email, or one that already has a
      // collection running, is refused. Both are answers about the account
      // rather than faults in the client, and reading them as outages would
      // tell somebody their client is broken when it is not.
      if (error.statusCode == 400 || error.statusCode == 403) return null;
      rethrow;
    }
  }

  /// Reads a whole standing record, or null when the body says there is
  /// none.
  static AccountDataPackage? readPayload(Object? payload) {
    if (payload is! Map) return null;
    return readPackage(payload.cast<String, Object?>());
  }

  /// Reads a record into what the page shows. A row without an id cannot be
  /// asked after again, so a record without one reads as no record rather
  /// than as a request nobody can name.
  static AccountDataPackage? readPackage(Map<String, Object?> payload) {
    final id = payload['harvest_id'];
    if (id is! String || id.isEmpty) return null;
    // The request was accepted, so a status this build does not know reads
    // as pending: the least-claiming thing that was already true.
    final status =
        DataPackageStatus.fromWire(payload['status']) ??
        DataPackageStatus.pending;
    final createdAt = _date(payload['created_at']) ?? DateTime(1970);
    return AccountDataPackage(
      harvestId: id,
      status: status,
      createdAt: createdAt,
      startedAt: _date(payload['started_at']),
      completedAt: _date(payload['completed_at']),
      failedAt: _date(payload['failed_at']),
      expiresAt: _date(payload['expires_at']),
      progressPercent: payload['progress_percent'] is num
          ? (payload['progress_percent']! as num).round().clamp(0, 100)
          : 0,
      progressStep: _string(payload['progress_step']),
      errorMessage: _string(payload['error_message']),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }
}
