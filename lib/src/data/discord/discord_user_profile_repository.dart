import 'dart:async';

import '../../domain/user_profile.dart';

/// The REST surface a profile edit needs.
abstract interface class DiscordUserProfileTransport {
  Future<Map<String, Object?>> readCurrentUser();

  /// `PATCH /users/@me`.
  ///
  /// Answers null when Discord refused the change — a wrong password, or a
  /// username already taken. Which status codes those are is the transport's
  /// business, not this layer's.
  Future<Map<String, Object?>?> patchCurrentUser(Map<String, Object?> body);
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

  @override
  UserProfile? get current => _current;

  @override
  Stream<UserProfile> get updates => _updates.stream;

  @override
  Future<UserProfile?> load() async {
    final payload = await _transport.readCurrentUser();
    return _install(payload);
  }

  @override
  Future<UserProfile?> apply(UserProfilePatch patch) async {
    if (patch.isEmpty) return _current;
    final payload = await _transport.patchCurrentUser(patch.toJson());
    // A refusal comes back as no payload rather than as a throw: a wrong
    // password and a username somebody else already has are both answers
    // about the request, and reporting either as an outage would be wrong.
    if (payload == null) return null;
    return _install(payload);
  }

  /// Applies a `USER_UPDATE` dispatch, which is how a change made on another
  /// device reaches this one.
  UserProfile? accept(String eventName, Map<String, Object?> data) {
    if (eventName != 'USER_UPDATE') return _current;
    return _install(data);
  }

  Future<void> close() async {
    if (!_updates.isClosed) await _updates.close();
  }

  UserProfile? _install(Map<String, Object?> payload) {
    final profile = readProfile(payload);
    if (profile == null) return _current;
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

  static String _text(Object? value) => value is String ? value : '';

  static String? _nullableText(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
