part of 'chat_models.dart';

/// R07's activity type enum.
///
/// [unrecognised] is not on the wire: Discord has added types before, and a
/// type this build has never seen must still render its name rather than crash
/// a member row or be silently mistaken for "Playing".
enum ActivityType {
  playing(0),
  streaming(1),
  listening(2),
  watching(3),
  customStatus(4),
  competing(5),
  hangStatus(6),
  unrecognised(-1);

  const ActivityType(this.wireValue);

  final int wireValue;

  static ActivityType fromWire(Object? value) => switch (value) {
    0 => playing,
    1 => streaming,
    2 => listening,
    3 => watching,
    4 => customStatus,
    5 => competing,
    6 => hangStatus,
    _ => unrecognised,
  };

  /// The word Discord puts in front of the activity name.
  ///
  /// Empty for the two types that are never rendered as a verb phrase: a
  /// custom status is the user's own sentence, and a hang status is a mood
  /// rather than something being done.
  String get verb => switch (this) {
    playing => 'Playing',
    streaming => 'Streaming',
    listening => 'Listening to',
    watching => 'Watching',
    competing => 'Competing in',
    customStatus || hangStatus || unrecognised => '',
  };
}

/// `activity.flags`, R07's `jUm`.
///
/// Values 4 and 8 are deliberately absent: the shipped enum jumps from
/// `JOIN = 2` to `SYNC = 16`, so a client that invented `SPECTATE = 4` would be
/// reading a bit Discord no longer sets.
abstract final class ActivityFlag {
  static const instance = 1;
  static const join = 2;
  static const sync = 16;
  static const play = 32;
  static const partyPrivacyFriends = 64;
  static const partyPrivacyVoiceChannel = 128;
  static const embedded = 256;
  static const contextless = 512;
  static const supportsRemoteActivityActionJoin = 1024;
  static const supportsJoinUrl = 2048;
}

/// `activity.status_display_type`: which of the three lines Discord promotes
/// into the one-line summary shown next to a name.
enum StatusDisplayType {
  name(0),
  state(1),
  details(2);

  const StatusDisplayType(this.wireValue);

  final int wireValue;

  static StatusDisplayType fromWire(Object? value) => switch (value) {
    1 => state,
    2 => details,
    _ => name,
  };
}

/// `activity.timestamps`, in epoch milliseconds.
final class ActivityTimestamps {
  const ActivityTimestamps({
    this.startMs,
    this.endMs,
    this.isCountDown = false,
  });

  final int? startMs;
  final int? endMs;

  /// R07's client-invented field: `end > created_at && type != LISTENING`.
  ///
  /// Not on the wire. It is what decides whether Discord shows time counting
  /// up from the start or down to the end, and a music track always counts up
  /// even though it has an end.
  final bool isCountDown;

  bool get isEmpty => startMs == null && endMs == null;

  /// How long the activity has been running at [now], or null when it carries
  /// no start.
  Duration? elapsedAt(DateTime now) {
    final start = startMs;
    if (start == null) return null;
    final elapsed = now.millisecondsSinceEpoch - start;
    return Duration(milliseconds: elapsed < 0 ? 0 : elapsed);
  }

  /// How long is left at [now], or null when the activity carries no end.
  Duration? remainingAt(DateTime now) {
    final end = endMs;
    if (end == null) return null;
    final remaining = end - now.millisecondsSinceEpoch;
    return Duration(milliseconds: remaining < 0 ? 0 : remaining);
  }
}

/// `activity.assets`, the two artwork slots a rich presence card draws.
final class ActivityAssets {
  const ActivityAssets({
    this.largeImage,
    this.largeText,
    this.largeUrl,
    this.smallImage,
    this.smallText,
    this.smallUrl,
    this.largeImageUrl,
    this.smallImageUrl,
  });

  final String? largeImage;
  final String? largeText;
  final String? largeUrl;
  final String? smallImage;
  final String? smallText;
  final String? smallUrl;

  /// The resolved artwork, or null when the key names a host this client does
  /// not know how to address.
  ///
  /// Resolved when the activity is mapped rather than when it is drawn: the
  /// key is only addressable together with the activity's `application_id`,
  /// which a widget several layers away no longer has.
  final String? largeImageUrl;
  final String? smallImageUrl;

  bool get isEmpty =>
      largeImage == null &&
      largeText == null &&
      largeUrl == null &&
      smallImage == null &&
      smallText == null &&
      smallUrl == null;
}

/// `activity.party.privacy`, R07's `KIY`.
enum ActivityPartyPrivacy {
  private(0),
  public(1);

  const ActivityPartyPrivacy(this.wireValue);

  final int wireValue;

  static ActivityPartyPrivacy? fromWire(Object? value) => switch (value) {
    0 => private,
    1 => public,
    _ => null,
  };
}

/// `activity.party`. `size` is a two-element `[current, max]` array on the
/// wire; both halves are kept null when it arrives any other length, because a
/// party card that reads "3 of 0" is worse than one that omits the count.
final class ActivityParty {
  const ActivityParty({this.id, this.currentSize, this.maxSize, this.privacy});

  final String? id;
  final int? currentSize;
  final int? maxSize;
  final ActivityPartyPrivacy? privacy;

  bool get hasSize => currentSize != null && maxSize != null;
}

/// `activity.secrets`. `spectate` is accepted on write but is not on the read
/// schema, so it is not modelled here.
final class ActivitySecrets {
  const ActivitySecrets({this.match, this.join});

  final String? match;
  final String? join;
}

/// The emoji beside a custom status.
///
/// `id == null` means a Unicode emoji whose [name] is the character itself;
/// otherwise [name] is the custom emoji's shortcode and [id] its snowflake.
final class ActivityEmoji {
  const ActivityEmoji({
    required this.name,
    this.id,
    this.animated = false,
    this.imageUrl,
  });

  final String name;
  final String? id;
  final bool animated;

  /// The CDN image for a custom emoji, resolved when the activity is mapped
  /// so that a row painting one does not have to know Discord's URL shapes.
  final String? imageUrl;

  bool get isCustom => id != null && id!.isNotEmpty;
}

/// One entry of a presence's `activities` array.
final class UserActivity {
  const UserActivity({
    required this.name,
    this.type = ActivityType.playing,
    this.sessionId,
    this.url,
    this.applicationId,
    this.statusDisplayType = StatusDisplayType.name,
    this.state,
    this.stateUrl,
    this.details,
    this.detailsUrl,
    this.emoji,
    this.assets,
    this.timestamps,
    this.party,
    this.secrets,
    this.syncId,
    this.createdAtMs,
    this.instance = false,
    this.flags = 0,
    this.platform,
    this.supportedPlatforms = const [],
    this.buttons = const [],
  });

  final String name;
  final ActivityType type;
  final String? sessionId;
  final String? url;
  final String? applicationId;
  final StatusDisplayType statusDisplayType;
  final String? state;
  final String? stateUrl;
  final String? details;
  final String? detailsUrl;
  final ActivityEmoji? emoji;
  final ActivityAssets? assets;
  final ActivityTimestamps? timestamps;
  final ActivityParty? party;
  final ActivitySecrets? secrets;
  final String? syncId;
  final int? createdAtMs;
  final bool instance;
  final int flags;
  final String? platform;
  final List<String> supportedPlatforms;

  /// Button labels. The gateway sends bare strings here; the `{label, url}`
  /// form only exists on the RPC write path, which this client does not serve.
  final List<String> buttons;

  bool hasFlag(int flag) => flags & flag == flag;

  /// R07's `isRichPresence` predicate, used by the activity comparator and by
  /// the profile card to decide whether an activity deserves a full card.
  bool get isRichPresence =>
      type != ActivityType.customStatus &&
      (details != null ||
          (assets != null &&
              (assets!.largeImage != null || assets!.smallText != null)) ||
          party != null ||
          secrets != null ||
          state != null);

  /// The single line Discord shows under a name for this activity.
  ///
  /// `status_display_type` picks which of the three strings is promoted; a
  /// custom status has no verb at all and reads as the user wrote it.
  String get summary {
    if (type == ActivityType.customStatus) return state ?? '';
    final promoted = switch (statusDisplayType) {
      StatusDisplayType.state => state,
      StatusDisplayType.details => details,
      StatusDisplayType.name => null,
    };
    final subject = (promoted == null || promoted.isEmpty) ? name : promoted;
    final verb = type.verb;
    return verb.isEmpty ? subject : '$verb $subject';
  }
}
