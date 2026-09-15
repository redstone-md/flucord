import '../../domain/account_connections.dart';
import 'discord_rest_client.dart';

/// The account's third-party connections, over the desktop-user session.
///
/// Linking hands off to the service's own page: the route answers with where
/// that page starts, and the rest of the exchange happens between the person
/// and the service, never through this client.
final class DiscordAccountConnectionsRepository
    implements AccountConnectionsRepository {
  DiscordAccountConnectionsRepository(this._rest);

  final DiscordRestClient _rest;

  @override
  Future<List<AccountConnection>> loadConnections() async =>
      readConnections(await _rest.getList('/users/@me/connections'));

  @override
  Future<String?> startLink(String type) async {
    final normalized = type.trim();
    if (normalized.isEmpty) return null;
    try {
      final payload = await _rest.requestObject(
        'GET',
        '/connections/${Uri.encodeComponent(normalized)}/authorize',
        query: const {'two_way_link_type': 'desktop'},
      );
      final url = payload['url'];
      return url is String && url.isNotEmpty ? url : null;
    } on DiscordApiException catch (error) {
      // A service Discord will no longer link, or one this account may not
      // link, answers with a refusal. Neither is an outage, and reporting it
      // as one would tell somebody their client is broken when the answer
      // is about the link they asked for.
      if (error.statusCode == 400 || error.statusCode == 403) return null;
      rethrow;
    }
  }

  @override
  Future<void> unlink(AccountConnection connection) async {
    try {
      await _rest.requestEmpty(
        'DELETE',
        '/users/@me/connections/${Uri.encodeComponent(connection.type)}'
            '/${Uri.encodeComponent(connection.id)}',
      );
    } on DiscordApiException catch (error) {
      // Discord refuses to remove a link it does not hold. The row on screen
      // came from a read that may be a moment behind, so this is an answer
      // about which link, not a fault in the client.
      if (error.statusCode == 400 || error.statusCode == 404) {
        throw const AccountConnectionException(
          AccountConnectionFailure.unlinkRefused,
        );
      }
      rethrow;
    }
  }

  /// Reads the connections payload.
  ///
  /// A row without an id or a name is dropped rather than shown as a blank:
  /// a link somebody cannot recognise is a link nobody can act on.
  static List<AccountConnection> readConnections(
    List<Map<String, Object?>> payload,
  ) => [
    for (final entry in payload)
      if (_connection(entry) case final AccountConnection connection)
        connection,
  ];

  static AccountConnection? _connection(Map<String, Object?> payload) {
    final id = payload['id'];
    final name = payload['name'];
    final type = payload['type'];
    if (id is! String || name is! String || type is! String || type.isEmpty) {
      return null;
    }
    return AccountConnection(
      id: id,
      type: type,
      name: name,
      revoked: payload['revoked'] == true,
      verified: payload['verified'] == true,
      friendSync: payload['friend_sync'] == true,
      showActivity: payload['show_activity'] == true,
      twoWayLink: payload['two_way_link'] == true,
      visibility: payload['visibility'] is int
          ? payload['visibility']! as int
          : 0,
    );
  }
}
