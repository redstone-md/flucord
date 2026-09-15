/// Where a request for the account's data has got to. Discord's own names,
/// kept as it writes them.
enum DataPackageStatus {
  pending('pending'),
  processing('processing'),
  completed('completed'),
  failed('failed');

  const DataPackageStatus(this.wireValue);

  final String wireValue;

  /// Reads the wire value, or null when Discord said something this build
  /// does not know. A status is never guessed higher or lower.
  static DataPackageStatus? fromWire(Object? value) {
    if (value is! String) return null;
    for (final status in DataPackageStatus.values) {
      if (status.wireValue == value) return status;
    }
    return null;
  }
}

/// One request for the account's data, as Discord's record of it stands.
///
/// The archive itself never arrives here: Discord collects it and emails a
/// download link. What this carries is where that collection has got to,
/// which is what the person waiting on it can actually read.
final class AccountDataPackage {
  const AccountDataPackage({
    required this.harvestId,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.failedAt,
    this.expiresAt,
    this.progressPercent = 0,
    this.progressStep,
    this.errorMessage,
  });

  /// Discord's own id for the request, which is what asks after it again.
  final String harvestId;

  final DataPackageStatus status;

  final DateTime createdAt;

  final DateTime? startedAt;

  final DateTime? completedAt;

  final DateTime? failedAt;

  /// When the download link Discord emailed stops working.
  final DateTime? expiresAt;

  /// How far the collection has got, between 0 and 100.
  final int progressPercent;

  /// What step the collection is on, in Discord's own words, when it says.
  final String? progressStep;

  /// Why it failed, in Discord's own words, when it says.
  final String? errorMessage;

  /// Whether a request is already running. Discord refuses a second while
  /// the first has not finished, so this is what keeps the page from
  /// offering one that could only be refused.
  bool get isRunning =>
      status == DataPackageStatus.pending ||
      status == DataPackageStatus.processing;
}

/// Asks Discord to collect the account's data, and says where that stands.
abstract interface class AccountDataPackageRepository {
  /// `GET /users/@me/harvest/latest`.
  ///
  /// Returns null when no request was ever made, which is the honest state of
  /// an account that never asked.
  Future<AccountDataPackage?> loadLatest();

  /// `POST /users/@me/harvest`.
  ///
  /// Returns null when Discord refused to start one, which it does for an
  /// account without a verified email address or one that already has a
  /// request running: an answer about the account, not a failure.
  Future<AccountDataPackage?> request();
}
