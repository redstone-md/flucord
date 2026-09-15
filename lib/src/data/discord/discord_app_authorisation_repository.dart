import '../../domain/app_authorisation.dart';
import '../../domain/discord_permissions.dart';
import 'discord_cdn.dart';
import 'discord_rest_client.dart';

/// Bot and app invites, over the desktop-user session.
///
/// The desktop client accepts an invite inside its own authorisation page: the
/// person sees the app, sees what it asked for, picks a server, and consents.
/// The routes here carry that same conversation, so adding a bot never needs
/// a browser this build does not open.
final class DiscordAppAuthorisationRepository
    implements AppAuthorisationRepository {
  DiscordAppAuthorisationRepository(this._rest);

  final DiscordRestClient _rest;

  @override
  AppInvite? parseInvite(Uri uri) {
    final applicationId = _applicationIdFrom(uri);
    if (applicationId == null) return null;
    final query = uri.queryParameters;
    final scopes = AppInvite.parseScopes(query['scope']);
    if (scopes.isEmpty) return null;
    final permissions = query['permissions'];
    return AppInvite(
      applicationId: applicationId,
      scopes: scopes,
      permissions:
          DiscordPermissions.tryParse(permissions) ?? DiscordPermissions.none,
      guildId: _snowflake(query['guild_id']),
    );
  }

  @override
  Future<AppInviteApplication> loadApplication(String applicationId) async =>
      readApplication(
        await _rest.getObject(
          '/applications/${Uri.encodeComponent(applicationId)}/public',
        ),
      );

  @override
  Future<void> consent({
    required AppInvite invite,
    required String guildId,
  }) async {
    try {
      // The consent route takes the invite's own parameters back, plus the
      // guild the person picked. No redirect or code: this is the
      // user-session form of the flow, which answers with where the desktop
      // client would go next and needs nothing done with it.
      await _rest.requestObject(
        'POST',
        '/oauth2/authorize/consent',
        body: {
          'client_id': invite.applicationId,
          'guild_id': guildId,
          'permissions': DiscordPermissions.encode(invite.permissions),
          'scope': invite.scopes.join(' '),
        },
      );
    } on DiscordApiException catch (error) {
      throw _failureFor(error);
    }
  }

  @override
  Future<List<AuthorisedApplication>> loadAuthorisedApplications() async =>
      readAuthorisedApplications(
        await _rest.getList('/oauth2/@me/authorizations'),
      );

  @override
  Future<void> revokeAuthorisedApplication(
    AuthorisedApplication application,
  ) async {
    try {
      await _rest.requestEmpty(
        'DELETE',
        '/oauth2/@me/authorizations/'
            '${Uri.encodeComponent(application.applicationId)}',
      );
    } on DiscordApiException catch (error) {
      // A grant Discord does not hold any more was already revoked, or was
      // never this account's to revoke. Either way it is an answer about
      // the grant, not a fault in the client.
      if (error.statusCode == 400 ||
          error.statusCode == 403 ||
          error.statusCode == 404) {
        throw const AppAuthorisationException(AppAuthorisationFailure.refused);
      }
      rethrow;
    }
  }

  /// Reads the grants payload.
  ///
  /// A row whose application carries no id names nothing and can be revoked
  /// by nothing, so it is dropped rather than shown as a blank nobody can
  /// act on.
  static List<AuthorisedApplication> readAuthorisedApplications(
    List<Map<String, Object?>> payload,
  ) => [
    for (final entry in payload)
      if (_authorisedApplication(entry) case final AuthorisedApplication app)
        app,
  ];

  static AuthorisedApplication? _authorisedApplication(
    Map<String, Object?> payload,
  ) {
    final application = payload['application'];
    if (application is! Map) return null;
    final id = application['id'];
    final name = application['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    return AuthorisedApplication(
      applicationId: id,
      name: name,
      description: application['description'] is String
          ? application['description']! as String
          : '',
      iconUrl: DiscordCdn.appIcon(
        id,
        application['icon'] is String ? application['icon']! as String : null,
      ),
      scopes: [
        if (payload['scopes'] case final List<Object?> raw)
          for (final scope in raw)
            if (scope is String) scope,
      ],
      authorizedAt: payload['authorized_at'] is String
          ? DateTime.tryParse(payload['authorized_at']! as String)?.toUtc()
          : null,
    );
  }

  /// Reads a refusal into which one it was, from the JSON code Discord put
  /// in the answer when it sent one.
  ///
  /// The guild cap (30001) and the missing-permission answer (50013) are
  /// refusals about this add, not outages. Anything else the server says
  /// about the person's standing in the guild or the app's availability
  /// reads as a plain refusal too, because guessing between them would be
  /// inventing detail Discord did not give. Only a status this list does
  /// not treat as an answer reads as a failure of the request itself.
  static AppAuthorisationException _failureFor(DiscordApiException error) {
    final code = error.responsePayload?['code'];
    if (code == 30001 || code == 50013) {
      return const AppAuthorisationException(AppAuthorisationFailure.refused);
    }
    if (error.statusCode == 400 || error.statusCode == 403) {
      return const AppAuthorisationException(AppAuthorisationFailure.refused);
    }
    return const AppAuthorisationException(AppAuthorisationFailure.denied);
  }

  /// Reads the public application payload an invite's page is built from.
  static AppInviteApplication readApplication(Map<String, Object?> payload) {
    final id = payload['id'];
    final name = payload['name'];
    final bot = payload['bot'];
    final botUsername = bot is Map && bot['username'] is String
        ? bot['username']! as String
        : '';
    return AppInviteApplication(
      id: id is String ? id : '',
      name: name is String && name.isNotEmpty ? name : botUsername,
      description: payload['description'] is String
          ? payload['description']! as String
          : '',
      iconUrl: id is String
          ? DiscordCdn.appIcon(
              id,
              payload['icon'] is String ? payload['icon']! as String : null,
            )
          : null,
      botUsername: botUsername,
      isPublic:
          payload['integration_public'] != false &&
          payload['bot_public'] != false,
    );
  }

  /// Reads the application id out of either form an invite arrives in.
  static String? _applicationIdFrom(Uri uri) {
    if (uri.host != 'discord.com' &&
        uri.host != 'ptb.discord.com' &&
        uri.host != 'canary.discord.com') {
      return null;
    }
    if (uri.path == '/oauth2/authorize' ||
        uri.path == '/api/oauth2/authorize') {
      return _snowflake(uri.queryParameters['client_id']);
    }
    if (uri.path == '/api/v9/oauth2/authorize') {
      return _snowflake(uri.queryParameters['client_id']);
    }
    return null;
  }

  static String? _snowflake(Object? value) =>
      value is String && RegExp(r'^\d+$').hasMatch(value) ? value : null;
}
