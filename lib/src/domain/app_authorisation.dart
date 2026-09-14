/// A bot or app invite, parsed out of the URL a share link carries.
///
/// Two forms reach this client: `discord.com/oauth2/authorize?...`, which an
/// app's own page builds, and `discord.gg/...`, which a bot invite cannot
/// use. Anything that is neither is not an app invite, and saying so is an
/// answer rather than an error.
final class AppInvite {
  AppInvite({
    required this.applicationId,
    required this.scopes,
    BigInt? permissions,
    this.guildId,
  }) : permissions = permissions ?? BigInt.zero;

  /// The application the invite adds.
  final String applicationId;

  /// What the app asked for, in the order the link listed them.
  final List<String> scopes;

  /// The permissions a bot invite asks to be granted on joining. Zero for an
  /// invite that names none, which is a real request and not a missing one.
  final BigInt permissions;

  /// The guild the link preselects, when it names one.
  final String? guildId;

  /// Whether the invite adds a bot, which is what the `bot` scope says.
  bool get addsBot => scopes.contains('bot');

  /// Whether the invite also registers its slash commands, which is what the
  /// `applications.commands` scope says.
  bool get addsCommands => scopes.contains('applications.commands');

  /// Reads the scopes out of a link, split as Discord writes them.
  static List<String> parseScopes(String? raw) => [
    for (final scope in (raw ?? '').split(RegExp(r'[ +]')))
      if (scope.trim().isNotEmpty) scope.trim(),
  ];

  @override
  bool operator ==(Object other) =>
      other is AppInvite &&
      other.applicationId == applicationId &&
      _sameScopes(other.scopes) &&
      other.permissions == permissions &&
      other.guildId == guildId;

  bool _sameScopes(List<String> other) {
    if (other.length != scopes.length) return false;
    for (var index = 0; index < scopes.length; index++) {
      if (other[index] != scopes[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(applicationId, Object.hashAll(scopes), permissions, guildId);
}

/// The app an invite adds, as Discord's public application record names it.
final class AppInviteApplication {
  const AppInviteApplication({
    required this.id,
    required this.name,
    this.description = '',
    this.iconUrl,
    this.botUsername = '',
    this.isPublic = true,
  });

  /// The application's own id.
  final String id;

  final String name;

  /// The app's own description of itself, in the localisation Discord sent.
  final String description;

  final String? iconUrl;

  /// The bot user's name, when the app has a bot.
  final String botUsername;

  /// Whether anybody may add the app. False means Discord refuses everyone
  /// but the app's own team, and the page says so rather than offering a
  /// button that can only fail.
  final bool isPublic;
}

/// One grant this account has already made to an app.
///
/// What a review needs, and nothing more: who was let in, what they were
/// given, and when. The grant itself lives on Discord's side; this row is
/// the account's own record of saying yes.
final class AuthorisedApplication {
  const AuthorisedApplication({
    required this.applicationId,
    required this.name,
    this.description = '',
    this.iconUrl,
    this.scopes = const [],
    this.authorizedAt,
  });

  /// The app the grant belongs to, which is also what names it on the
  /// removal route.
  final String applicationId;

  final String name;

  final String description;

  /// The app's icon, when Discord sent the hash for it.
  final String? iconUrl;

  /// What the app was given, in the words Discord names scopes by.
  final List<String> scopes;

  final DateTime? authorizedAt;

  @override
  bool operator ==(Object other) =>
      other is AuthorisedApplication &&
      other.applicationId == applicationId &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(applicationId, name, description);
}

/// Why an authorisation did not happen.
enum AppAuthorisationFailure {
  /// The person, or Discord, said no to adding the app.
  denied,

  /// Discord refused the add for a reason about the account or the guild:
  /// the person does not manage the guild, the app is private, or the guild
  /// is full.
  refused,
}

/// A refusal from the authorisation flow, naming which one it was.
final class AppAuthorisationException implements Exception {
  const AppAuthorisationException(this.failure);

  final AppAuthorisationFailure failure;

  @override
  String toString() => 'AppAuthorisationException($failure)';
}

/// Parses bot and app invites, states what they ask for, and adds the app to
/// a chosen guild on consent.
abstract interface class AppAuthorisationRepository {
  /// Parses a link into an [AppInvite], or null when it is not an app
  /// invite.
  AppInvite? parseInvite(Uri uri);

  /// `GET /applications/{id}`: the public record an invite's page is built
  /// from, so the person can see who they are letting in before they do.
  Future<AppInviteApplication> loadApplication(String applicationId);

  /// Consents to [invite] and adds the app to [guildId].
  ///
  /// Throws [AppAuthorisationException] when Discord refused, so the page
  /// can say which refusal it was.
  Future<void> consent({required AppInvite invite, required String guildId});

  /// `GET /oauth2/@me/authorizations`: every app this account has let in.
  Future<List<AuthorisedApplication>> loadAuthorisedApplications();

  /// `DELETE /oauth2/@me/authorizations/{id}`, which takes the whole grant
  /// back.
  ///
  /// Throws [AppAuthorisationException] when Discord refused, so the page
  /// can name the app rather than read the refusal as an outage.
  Future<void> revokeAuthorisedApplication(AuthorisedApplication application);
}
