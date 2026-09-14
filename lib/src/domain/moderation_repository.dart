import 'moderation_report.dart';

/// The user-facing safety actions a session can take on its own behalf.
///
/// Separate from `GuildManagementRepository` because these are not moderator
/// powers: reporting and blocking belong to whoever is signed in, need no
/// permission in any guild, and exist on transports that can administer
/// nothing. A single contract would force a caller holding one to claim the
/// other.
abstract interface class ModerationRepository {
  /// Fetches the form graph for [type].
  ///
  /// The renderer awaits this *before* opening the modal, so a failure means no
  /// modal at all rather than an empty one.
  Future<ReportMenu> loadReportMenu(ReportType type, {String? variant});

  /// Sends a completed report. Answers the server-minted report id, or `null`
  /// when the response carried none.
  Future<String?> submitReport(ReportSubmission submission);

  /// `PUT /users/@me/relationships/{id}` with `type: 2`.
  Future<void> blockUser(String userId);

  /// Unblocking and unfriending are the same request; the caller decides which
  /// it means by which button it put on screen.
  Future<void> unblockUser(String userId);

  /// Ignoring is its own sub-resource, not a relationship type: it sets
  /// `user_ignored` on whatever relationship already exists and leaves a
  /// friendship intact.
  Future<void> ignoreUser(String userId);

  Future<void> unignoreUser(String userId);
}
