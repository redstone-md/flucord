import 'chat_models.dart';

/// One activity a game asked this client to publish over the local RPC
/// interface.
///
/// A game builds the activity it wants shown: the card's lines, artwork,
/// timestamps, party and secrets. Everything else this client adds (the name
/// of the game as it detects it, the playing type) is not the game's to
/// choose, so the server applies the documented limits itself.
final class RichPresenceActivity {
  const RichPresenceActivity({
    this.clientId,
    this.name,
    this.type,
    this.state,
    this.details,
    this.timestamps,
    this.assets,
    this.party,
    this.secrets,
    this.instance,
    this.buttons,
  });

  /// The game's application id, from the handshake that opened the
  /// connection. An activity without one is not shareable, R07-style, so
  /// this rides along and the composer's own gate decides.
  final String? clientId;

  final String? name;
  final int? type;
  final String? state;
  final String? details;
  final Map<String, Object?>? timestamps;
  final Map<String, Object?>? assets;
  final Map<String, Object?>? party;
  final Map<String, Object?>? secrets;
  final bool? instance;
  final List<Object?>? buttons;

  /// Builds from a `SET_ACTIVITY` payload's `activity` object, carrying the
  /// handshake's client id.
  ///
  /// A payload this server cannot read answers null rather than an activity
  /// with the text stripped off: showing "the game is playing" with none of
  /// what the game wrote would be worse than showing nothing.
  static RichPresenceActivity? fromPayload(
    Object? payload, {
    String? clientId,
  }) {
    if (payload is! Map) return null;
    final args = payload['args'];
    if (args is! Map) return null;
    final activity = args['activity'];
    if (activity is! Map) return null;
    final name = args['name'];
    return RichPresenceActivity(
      clientId: clientId,
      name: name is String && name.isNotEmpty ? name : null,
      type: activity['type'] is int ? activity['type'] as int : null,
      state: _string(activity['state']),
      details: _string(activity['details']),
      timestamps: _map(activity['timestamps']),
      assets: _map(activity['assets']),
      party: _map(activity['party']),
      secrets: _map(activity['secrets']),
      instance: activity['instance'] is bool
          ? activity['instance'] as bool
          : null,
      buttons: activity['buttons'] is List
          ? List<Object?>.from(activity['buttons'] as List)
          : null,
    );
  }
}

/// The documented local Rich Presence interface.
///
/// A game connects over the IPC socket, handshakes with its application id,
/// and sends SET_ACTIVITY commands; the server reflects what arrives into
/// this account's own presence. It is its own surface, not a route through
/// the desktop-user session: the frames never touch the gateway, and the
/// server shuts down with the app.
abstract interface class RichPresenceService {
  /// Whether the server is listening.
  bool get isRunning;

  /// The activities the games currently connected have published, in the
  /// order the connections asked.
  List<UserActivity> get activities;

  /// Emits whenever [activities] changes.
  Stream<List<UserActivity>> get activitiesUpdates;

  /// Starts listening. Answers whether the socket opened.
  Future<bool> start();

  /// Stops listening and closes every connected game's session.
  Future<void> stop();
}

/// Builds the [UserActivity] one SET_ACTIVITY publishes, applying the
/// documented limits.
///
/// The RPC surface restricts an activity to the playing, listening, watching
/// and competing types; anything else arrives as playing. The activity is
/// named for the game that sent it: the payload's own `args.name` wins, and
/// [gameName] is what a game that named nothing is shown under. The client id
/// rides along, which is what makes the activity shareable through the same
/// gate the detected games pass.
UserActivity? richPresenceToActivity(
  RichPresenceActivity payload, {
  required String gameName,
}) {
  final type = switch (payload.type) {
    0 => ActivityType.playing,
    2 => ActivityType.listening,
    3 => ActivityType.watching,
    5 => ActivityType.competing,
    _ => ActivityType.playing,
  };
  final state = payload.state;
  final details = payload.details;
  final assets = payload.assets;
  final party = payload.party;
  final secrets = payload.secrets;
  final timestamps = payload.timestamps;
  final instance = payload.instance;
  final activity = UserActivity(
    name: payload.name ?? gameName,
    type: type,
    applicationId: payload.clientId,
    state: state,
    details: details,
    timestamps: _timestampsFrom(timestamps),
    assets: _assetsFrom(assets),
    party: _partyFrom(party),
    secrets: _secretsFrom(secrets),
    instance: instance ?? false,
    flags: instance ?? false ? ActivityFlag.instance : 0,
  );
  if (activity.type == ActivityType.playing &&
      !activity.isRichPresence &&
      state == null &&
      details == null) {
    return null;
  }
  return activity;
}

ActivityTimestamps? _timestampsFrom(Map<String, Object?>? payload) {
  if (payload == null) return null;
  final start = _int(payload['start']);
  final end = _int(payload['end']);
  if (start == null && end == null) return null;
  return ActivityTimestamps(startMs: start, endMs: end);
}

ActivityAssets? _assetsFrom(Map<String, Object?>? payload) {
  if (payload == null) return null;
  final largeImage = _string(payload['large_image']);
  final largeText = _string(payload['large_text']);
  final smallImage = _string(payload['small_image']);
  final smallText = _string(payload['small_text']);
  if (largeImage == null &&
      largeText == null &&
      smallImage == null &&
      smallText == null) {
    return null;
  }
  return ActivityAssets(
    largeImage: largeImage,
    largeText: largeText,
    smallImage: smallImage,
    smallText: smallText,
  );
}

ActivityParty? _partyFrom(Map<String, Object?>? payload) {
  if (payload == null) return null;
  final id = _string(payload['id']);
  final size = payload['size'];
  final currentSize = size is List && size.isNotEmpty ? _int(size[0]) : null;
  final maxSize = size is List && size.length > 1 ? _int(size[1]) : null;
  if (id == null && currentSize == null) return null;
  return ActivityParty(id: id, currentSize: currentSize, maxSize: maxSize);
}

ActivitySecrets? _secretsFrom(Map<String, Object?>? payload) {
  if (payload == null) return null;
  final join = _string(payload['join']);
  final spectate = _string(payload['spectate']);
  final match = _string(payload['match']);
  if (join == null && spectate == null && match == null) return null;
  return ActivitySecrets(join: join, match: match);
}

int? _int(Object? value) => value is int ? value : null;

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

Map<String, Object?>? _map(Object? value) =>
    value is Map && value.isNotEmpty ? Map<String, Object?>.from(value) : null;
