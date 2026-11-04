/// A service Discord links accounts with. Each value's name is the service's
/// `type` on the wire.
enum ConnectionService {
  battlenet('Battle.net'),
  bluesky('Bluesky', page: 'https://bsky.app/profile/', pageById: true),
  domain('Domain', page: 'https://'),
  ebay('eBay', page: 'https://www.ebay.com/usr/'),
  epicgames('Epic Games'),
  github('GitHub', page: 'https://github.com/'),
  instagram('Instagram', page: 'https://www.instagram.com/'),
  leagueoflegends('League of Legends'),
  playstation('PlayStation Network'),
  reddit('Reddit', page: 'https://www.reddit.com/user/'),
  riotgames('Riot Games'),
  roblox(
    'Roblox',
    page: 'https://www.roblox.com/users/',
    pageById: true,
    pageSuffix: '/profile',
  ),
  spotify('Spotify', page: 'https://open.spotify.com/user/', pageById: true),
  steam('Steam', page: 'https://steamcommunity.com/profiles/', pageById: true),
  tiktok('TikTok', page: 'https://www.tiktok.com/@'),
  twitch('Twitch', page: 'https://www.twitch.tv/'),
  twitter('X / Twitter', page: 'https://x.com/'),
  youtube('YouTube', page: 'https://www.youtube.com/channel/', pageById: true);

  const ConnectionService(
    this.label, {
    String? page,
    bool pageById = false,
    String pageSuffix = '',
  }) : _page = page,
       _pageById = pageById,
       _pageSuffix = pageSuffix;

  /// What the service calls itself.
  final String label;

  /// Where an account's page starts, or null for a service with no public
  /// page, such as Battle.net.
  final String? _page;

  /// Whether the page is named by the account's id rather than its name.
  final bool _pageById;
  final String _pageSuffix;

  static ConnectionService? byType(String type) => values.asNameMap()[type];

  /// What to call the service Discord names [type]. A service not listed
  /// here takes Discord's own identifier, capitalised, rather than wording
  /// invented here.
  static String nameOf(String type) =>
      byType(type)?.label ??
      type
          .split(RegExp(r'[_-]+'))
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');

  /// The account's page on the service, built the way Discord's client
  /// builds it, or null where there is none.
  Uri? pageOf({required String name, required String id}) {
    final page = _page;
    final part = _pageById ? id : name;
    if (page == null || part.isEmpty) return null;
    return Uri.tryParse('$page${Uri.encodeComponent(part)}$_pageSuffix');
  }
}

/// One third-party account linked to this Discord account.
///
/// The id is the third party's own id for the account, not a Discord
/// snowflake, and the pair of it with [type] is what names a connection on
/// the wire.
final class AccountConnection {
  const AccountConnection({
    required this.id,
    required this.type,
    required this.name,
    this.revoked = false,
    this.verified = false,
    this.friendSync = false,
    this.showActivity = false,
    this.twoWayLink = false,
    this.visibility = 0,
  });

  /// The third party's id for this account. Empty on a payload that carried
  /// none, which is a fact about the link rather than an error.
  final String id;

  /// Discord's own name for the service: `spotify`, `steam`, `github`.
  final String type;

  /// The username on the third-party service.
  final String name;

  /// The service took its access back. Discord keeps the row so the profile
  /// still shows what broke; unlinking it is the account's own decision.
  final bool revoked;

  final bool verified;
  final bool friendSync;
  final bool showActivity;
  final bool twoWayLink;

  /// Discord's `visibility`: 0 is only the account itself, 1 is everyone.
  final int visibility;

  bool get isPublic => visibility == 1;

  String get serviceName => ConnectionService.nameOf(type);

  @override
  bool operator ==(Object other) =>
      other is AccountConnection &&
      other.id == id &&
      other.type == type &&
      other.name == name &&
      other.revoked == revoked &&
      other.verified == verified &&
      other.friendSync == friendSync &&
      other.showActivity == showActivity &&
      other.twoWayLink == twoWayLink &&
      other.visibility == visibility;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    name,
    revoked,
    verified,
    friendSync,
    showActivity,
    twoWayLink,
    visibility,
  );
}

/// Why a link or unlink did not happen.
///
/// Each value is an answer Discord gives, and reporting one as an outage
/// would tell somebody their client is broken when the truth is about their
/// account or their request.
enum AccountConnectionFailure {
  /// Discord refused to start the link: the account is not eligible for it,
  /// or the service is already linked. The wire answers both the same way,
  /// so no value claims to tell them apart.
  refused,

  /// Discord refused to remove the link.
  unlinkRefused,
}

/// A refusal from the connections routes, naming which one it was.
final class AccountConnectionException implements Exception {
  const AccountConnectionException(this.failure);

  final AccountConnectionFailure failure;

  @override
  String toString() => 'AccountConnectionException($failure)';
}

/// Reads, links and unlinks the account's third-party connections.
abstract interface class AccountConnectionsRepository {
  /// `GET /users/@me/connections`.
  Future<List<AccountConnection>> loadConnections();

  /// `GET /connections/{type}/authorize`.
  ///
  /// The whole of the linking itself happens on the service's own page: this
  /// returns where it starts, and nothing about the third-party credentials
  /// passes through Flucord.
  ///
  /// Returns the URL, or null when Discord will not offer the link, which it
  /// does for a service that can no longer be added.
  Future<String?> startLink(String type);

  /// `DELETE /users/@me/connections/{type}/{id}`.
  ///
  /// Throws [AccountConnectionException] when Discord refused, so the
  /// settings page can say which refusal it was rather than reading every
  /// one as an outage.
  Future<void> unlink(AccountConnection connection);
}
