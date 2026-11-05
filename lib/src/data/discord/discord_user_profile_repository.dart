import 'dart:async';

import '../../app_log.dart';
import '../../domain/profile_effect.dart';
import '../../domain/profile_frame.dart';
import '../../domain/user_profile.dart';
import 'discord_cdn.dart';
import 'discord_mapper.dart';
import 'discord_profile_effects.dart';
import 'discord_profile_frames.dart';

/// The REST surface a profile edit needs.
abstract interface class DiscordUserProfileTransport {
  Future<Map<String, Object?>> readCurrentUser();

  /// `PATCH /users/@me`.
  ///
  /// Answers null when Discord refused the change — a wrong password, or a
  /// username already taken. Which status codes those are is the transport's
  /// business, not this layer's.
  Future<Map<String, Object?>?> patchCurrentUser(Map<String, Object?> body);

  /// `PATCH /users/@me/profile`, for what Discord keeps only on the profile.
  /// Answers the profile as saved.
  Future<Map<String, Object?>> patchCurrentProfile(Map<String, Object?> body);

  /// `GET /users/{id}/profile?with_mutual_guilds=true&with_mutual_friends=true`,
  /// plus `guild_id` when [guildId] is given, which adds the server profile.
  ///
  /// Answers null when Discord refused the read (403 or 404), which the route
  /// does for somebody this account has no relationship with at all. Any
  /// other failure throws. The mutuals are asked for up front: the popover
  /// wants them, and a second request per open would only save a round trip
  /// for a profile with none.
  Future<Map<String, Object?>?> readUserProfile(
    String userId, {
    String? guildId,
  });

  /// `GET /collectibles-products/{skuId}`: the shop's product for one
  /// item, as `{items: [...]}`.
  Future<Map<String, Object?>> readCollectiblesProduct(String skuId);

  /// `GET /storefront/products/skus`: the shop's description of the items
  /// [skuIds] name, as `{products: [{items: [...]}]}`.
  Future<Map<String, Object?>> readStoreProducts(List<String> skuIds);
}

/// The account's own profile over the desktop-user transport.
///
/// Every write is followed by the server's echo rather than by assuming the
/// patch applied: Discord normalises a display name, rejects a bio that is too
/// long, and returns a fresh CDN hash for an uploaded image. Trusting the local
/// draft would leave the UI showing something the account does not have.
final class DiscordUserProfileRepository implements UserProfileRepository {
  DiscordUserProfileRepository(this._transport);

  final DiscordUserProfileTransport _transport;
  final StreamController<UserProfile> _updates = StreamController.broadcast();

  UserProfile? _current;
  OtherUserProfile? _published;

  /// How each effect looks, by SKU, read once per session per effect.
  final Map<String, Future<ProfileEffectConfig?>> _effects = {};

  /// The profiles [loadProfileOf] answered, by user and server, oldest
  /// first. At most [_heldProfiles] stay.
  final Map<(String, String?), OtherUserProfile> _held = {};
  static const _heldProfiles = 200;

  /// How each frame looks, by SKU, read once per session per frame.
  final Map<String, Future<ProfileFrameConfig?>> _frames = {};

  @override
  UserProfile? get current => _current;

  @override
  Stream<UserProfile> get updates => _updates.stream;

  @override
  OtherUserProfile? get published => _published;

  /// Reads the user object, then the published profile once, for the theme
  /// colours the user object does not carry and for [published].
  ///
  /// The published profile is extra: when its read fails, such as on a rate
  /// limit, the editor still loads, without a theme or collectibles.
  @override
  Future<UserProfile?> load() async {
    final profile = readProfile(await _transport.readCurrentUser());
    if (profile == null) return _current;
    try {
      _published = await loadProfileOf(profile.userId);
    } on Object {
      _published = null;
    }
    return _publish(profile.withThemeColors(_published?.themeColors));
  }

  @override
  Future<UserProfile?> apply(UserProfilePatch patch) async {
    if (patch.isEmpty) return _current;
    final user = patch.toJson();
    if (user.isNotEmpty) {
      final payload = await _transport.patchCurrentUser(user);
      // A refusal comes back as no payload rather than as a throw: a wrong
      // password and a username somebody else already has are both answers
      // about the request, and reporting either as an outage would be wrong.
      if (payload == null) return null;
      _install(payload);
    }
    final profile = patch.toProfileJson();
    final current = _current;
    if (profile.isEmpty || current == null) return current;
    final saved = await _transport.patchCurrentProfile(profile);
    return _publish(
      current.withThemeColors(_themeColors(saved['theme_colors'])),
    );
  }

  @override
  Future<OtherUserProfile?> loadProfileOf(
    String userId, {
    String? serverId,
  }) async {
    if (userId.trim().isEmpty) return null;
    final key = (userId, serverId);
    final payload = await _transport.readUserProfile(userId, guildId: serverId);
    final profile = payload == null
        ? null
        : await _withLooks(payload, serverId);
    _held.remove(key);
    if (profile != null) {
      _held[key] = profile;
      if (_held.length > _heldProfiles) _held.remove(_held.keys.first);
    }
    return profile;
  }

  @override
  OtherUserProfile? heldProfileOf(String userId, {String? serverId}) =>
      _held[(userId, serverId)];

  /// The profile in [payload], with how its effect and frame look.
  Future<OtherUserProfile?> _withLooks(
    Map<String, Object?> payload,
    String? serverId,
  ) async {
    final profile = readOtherProfile(payload, serverId: serverId);
    // An expired effect or frame is never drawn, so the shop is not asked
    // about it.
    final now = DateTime.now();
    final effect = switch (profile?.effectiveProfileEffect) {
      final worn? when worn.isWornAt(now) => worn,
      _ => null,
    };
    final frame = switch (profile?.profileFrame) {
      final worn? when worn.isWornAt(now) => worn,
      _ => null,
    };
    if (effect == null && frame == null) return profile;
    final (effectConfig, frameConfig) = await (
      effect == null
          ? Future.value()
          : _described(
              _effects,
              effect.skuId,
              () => _transport
                  .readCollectiblesProduct(effect.skuId)
                  .then(
                    (product) =>
                        DiscordProfileEffects.read(product, effect.skuId),
                  ),
            ),
      frame == null
          ? Future.value()
          : _described(
              _frames,
              frame.skuId,
              () => _transport
                  .readStoreProducts([frame.skuId])
                  .then(
                    (payload) =>
                        DiscordProfileFrames.read(payload, frame.skuId),
                  ),
            ),
    ).wait;
    return readOtherProfile(
      payload,
      serverId: serverId,
      profileEffectConfig: effectConfig,
      profileFrameConfig: frameConfig,
    );
  }

  /// How the item [skuId] looks, from [cache] or else from [read], which
  /// asks the shop. Null where the shop does not describe it or could not be
  /// read; a failed read is tried again by the next profile that wears it.
  Future<T?> _described<T>(
    Map<String, Future<T?>> cache,
    String skuId,
    Future<T?> Function() read,
  ) async {
    final described = cache[skuId] ??= read();
    try {
      return await described;
    } on Object catch (error) {
      _log('Reading the shop item $skuId failed: $error');
      if (identical(cache[skuId], described)) cache.remove(skuId);
      return null;
    }
  }

  static void _log(String message) =>
      AppLog.warning('discord.profile', message);

  /// Applies a `USER_UPDATE` dispatch, which is how a change made on another
  /// device reaches this one.
  UserProfile? accept(String eventName, Map<String, Object?> data) {
    if (eventName != 'USER_UPDATE') return _current;
    return _install(data);
  }

  Future<void> close() async {
    if (!_updates.isClosed) await _updates.close();
  }

  /// Takes a user object, which has no theme colours, so the known ones
  /// stay.
  UserProfile? _install(Map<String, Object?> payload) {
    final profile = readProfile(payload);
    if (profile == null) return _current;
    return _publish(profile.withThemeColors(_current?.themeColors));
  }

  UserProfile _publish(UserProfile profile) {
    _current = profile;
    if (!_updates.isClosed) _updates.add(profile);
    return profile;
  }

  /// Maps a user object, skipping anything without an id.
  ///
  /// `global_name`, `bio` and `pronouns` are null on an account that never set
  /// them, and an empty string is the value the edit form needs, so both
  /// collapse to empty rather than being carried as null through the UI.
  static UserProfile? readProfile(Map<String, Object?> payload) {
    final id = payload['id'];
    if (id is! String || id.isEmpty) return null;
    return UserProfile(
      userId: id,
      username: _text(payload['username']),
      displayName: _text(payload['global_name']),
      discriminator: _text(payload['discriminator']),
      bio: _text(payload['bio']),
      pronouns: _text(payload['pronouns']),
      avatarHash: _nullableText(payload['avatar']),
      bannerHash: _nullableText(payload['banner']),
      accentColor: payload['accent_color'] is int
          ? payload['accent_color']! as int
          : null,
    );
  }

  /// Maps a `GET /users/{id}/profile` answer.
  ///
  /// The route nests the editable half under `user_profile` and the identity
  /// half under `user`, and redacts several fields for a private profile or a
  /// user who blocked this account. Anything absent stays absent rather than
  /// guessing: an empty bio and no bio read the same to the popover.
  ///
  /// Either level can carry the banner on its profile half or only on its
  /// identity half (`user`, `guild_member`), so the second backs up the first.
  /// The server profile is read only for the [serverId] that was asked for.
  static OtherUserProfile? readOtherProfile(
    Map<String, Object?> payload, {
    String? serverId,
    ProfileEffectConfig? profileEffectConfig,
    ProfileFrameConfig? profileFrameConfig,
  }) {
    final user = _object(payload['user']);
    if (user == null) return null;
    final id = user['id'];
    if (id is! String || id.isEmpty) return null;
    final metadata = _object(payload['user_profile']) ?? const {};
    return OtherUserProfile(
      userId: id,
      username: _text(user['username']),
      displayName: _text(user['global_name']),
      discriminator: _text(user['discriminator']),
      bio: _text(metadata['bio']),
      pronouns: _text(metadata['pronouns']),
      avatarHash: _nullableText(user['avatar']),
      bannerHash:
          _metadataText(metadata['banner']) ?? _metadataText(user['banner']),
      accentColor: metadata['accent_color'] is int
          ? metadata['accent_color']! as int
          : null,
      themeColors: _themeColors(metadata['theme_colors']),
      tags: DiscordMapper.tags(user),
      badges: [
        for (final badge in _objects(payload['badges']))
          if (_text(badge['id']).isNotEmpty)
            ProfileBadge(
              id: _text(badge['id']),
              description: _text(badge['description']),
              icon: _text(badge['icon']),
              link: _nullableText(badge['link']),
            ),
      ],
      connections: [
        for (final connection in _objects(payload['connected_accounts']))
          if (_text(connection['type']).isNotEmpty &&
              _text(connection['name']).isNotEmpty)
            ProfileConnection(
              type: _text(connection['type']),
              name: _text(connection['name']),
              id: _text(connection['id']),
              verified: connection['verified'] == true,
            ),
      ],
      mutualServers: [
        for (final guild in _objects(payload['mutual_guilds']))
          if (_text(guild['id']).isNotEmpty)
            MutualServer(
              id: _text(guild['id']),
              nickname: _nullableText(guild['nick']),
            ),
      ],
      mutualFriends: [
        for (final friend in _objects(payload['mutual_friends']))
          if (_text(friend['id']).isNotEmpty)
            MutualFriend(
              id: _text(friend['id']),
              displayName: _text(friend['global_name']).isNotEmpty
                  ? _text(friend['global_name'])
                  : _text(friend['username']),
              username: _nullableText(friend['username']),
              avatarUrl: DiscordCdn.userAvatar(
                _text(friend['id']),
                _nullableText(friend['avatar']),
                size: 32,
              ),
            ),
      ],
      serverProfile: serverId == null
          ? null
          : _readServerProfile(payload, serverId),
      profileEffect: ProfileEffect.fromJson(metadata['profile_effect']),
      profileEffectConfig: profileEffectConfig,
      profileFrame: ProfileFrame.fromCollectibles(metadata['collectibles']),
      profileFrameConfig: profileFrameConfig,
    );
  }

  static ServerProfile? _readServerProfile(
    Map<String, Object?> payload,
    String serverId,
  ) {
    final profile = _object(payload['guild_member_profile']);
    final member = _object(payload['guild_member']) ?? const {};
    if (profile == null) return null;
    return ServerProfile(
      guildId: serverId,
      bio: _metadataText(profile['bio']),
      pronouns: _metadataText(profile['pronouns']),
      bannerHash:
          _metadataText(profile['banner']) ?? _metadataText(member['banner']),
      themeColors: _themeColors(profile['theme_colors']),
      profileEffect: ProfileEffect.fromJson(profile['profile_effect']),
    );
  }

  /// `theme_colors` is `[primary, accent]`, or null where none is set.
  static ProfileThemeColors? _themeColors(Object? value) => switch (value) {
    [final int primary, final int accent] => ProfileThemeColors(
      primary,
      accent,
    ),
    _ => null,
  };

  /// The profile metadata spells an absent banner as null and an absent bio
  /// as an absent key, and both collapse here.
  static String? _metadataText(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static Map<String, Object?>? _object(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;

  static Iterable<Map<String, Object?>> _objects(Object? value) => [
    if (value is List)
      for (final item in value)
        if (item is Map) item.cast<String, Object?>(),
  ];

  static String _text(Object? value) => value is String ? value : '';

  static String? _nullableText(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
