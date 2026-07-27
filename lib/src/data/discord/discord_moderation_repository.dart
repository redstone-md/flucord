import '../../domain/moderation_report.dart';
import '../../domain/moderation_repository.dart';
import 'discord_report_mapper.dart';
import 'discord_rest_client.dart';

/// The user-facing safety routes over the desktop-user session.
///
/// Reporting and blocking are actions the signed-in account takes on its own
/// behalf, so unlike guild administration nothing here is gated on a permission
/// bit. They are also strictly user-initiated: nothing in this class runs on a
/// timer, a retry, or a gateway event.
final class DiscordModerationRepository implements ModerationRepository {
  const DiscordModerationRepository(this._rest);

  /// `type: 2` on a relationship is BLOCKED.
  static const _blockedRelationshipType = 2;

  final DiscordRestClient _rest;

  @override
  Future<ReportMenu> loadReportMenu(ReportType type, {String? variant}) async {
    final payload = await _rest.requestObject(
      'GET',
      '/reporting/menu/${Uri.encodeComponent(type.wireName)}',
      query: {'variant': variant},
    );
    final menu = DiscordReportMapper.menu(payload);
    // The renderer awaits the menu before it opens the modal, so a menu it
    // cannot walk means no modal at all. Failing here rather than opening an
    // empty form is what keeps a user from typing a report into nothing.
    if (menu == null) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Report menu is missing its node graph',
      );
    }
    return menu;
  }

  @override
  Future<String?> submitReport(ReportSubmission submission) async {
    final payload = await _rest.requestObject(
      'POST',
      '/reporting/${Uri.encodeComponent(submission.type.wireName)}',
      body: submission.body,
    );
    final id = payload['report_id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  @override
  Future<void> blockUser(String userId) => _rest.requestEmpty(
    'PUT',
    '/users/@me/relationships/${Uri.encodeComponent(userId)}',
    body: const {'type': _blockedRelationshipType},
  );

  /// The same request unfriends. Discord has one route for "remove whatever
  /// relationship exists", and which of the two it is depends only on what the
  /// caller put on screen.
  @override
  Future<void> unblockUser(String userId) => _rest.requestEmpty(
    'DELETE',
    '/users/@me/relationships/${Uri.encodeComponent(userId)}',
  );

  @override
  Future<void> ignoreUser(String userId) => _rest.requestEmpty(
    'PUT',
    '/users/@me/relationships/${Uri.encodeComponent(userId)}/ignore',
  );

  @override
  Future<void> unignoreUser(String userId) => _rest.requestEmpty(
    'DELETE',
    '/users/@me/relationships/${Uri.encodeComponent(userId)}/ignore',
  );
}
