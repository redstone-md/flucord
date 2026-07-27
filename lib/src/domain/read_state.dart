import 'chat_models.dart';
import 'discord_snowflake.dart';

part 'notification_settings.dart';
part 'read_state_snapshot.dart';

/// The kind of entity a read state tracks (R04 `read_state_type`).
///
/// The number is part of the wire contract twice over: it selects which entry
/// dialect READY used, and it is interpolated straight into the non-channel ACK
/// paths, so the value — not the name — is what has to survive round trips.
enum ReadStateType {
  channel(0),
  guildEvent(1),
  notificationCenter(2),
  guildHome(3),
  guildOnboardingQuestion(4),
  messageRequests(5);

  const ReadStateType(this.wireValue);

  final int wireValue;

  /// Types acknowledged under a guild: `POST /guilds/{g}/ack/{type}/{entity}`.
  bool get isGuildScoped =>
      this == guildEvent ||
      this == guildHome ||
      this == guildOnboardingQuestion;

  /// Types acknowledged under the account: `POST /users/@me/{type}/{id}/ack`.
  bool get isUserScoped =>
      this == notificationCenter || this == messageRequests;

  /// The type a wire value names, or `null` when this build does not model it.
  ///
  /// An absent field means [channel], which is what Discord's own default is.
  /// An unknown *number* is deliberately dropped instead: a later type keyed by
  /// a guild id would otherwise be filed as the read state of whichever channel
  /// happens to share that id, and silently blank its unread badge.
  static ReadStateType? fromWire(Object? value) {
    if (value == null) return channel;
    if (value is! int) return null;
    for (final type in values) {
      if (type.wireValue == value) return type;
    }
    return null;
  }
}

/// Bits Discord writes into a read state's `flags`.
///
/// R04 records the computation (`thread ? 2 : guild channel ? 1 : 0`) and the
/// one bit the client reads back, but the bundle carries no named enum for
/// them, so these names are this client's reading of that computation rather
/// than a symbol lifted from Discord.
abstract final class ReadStateFlags {
  static const guildChannel = 1;
  static const thread = 2;
  static const mentionLowImportance = 1 << 2;

  /// The value an outbound channel ACK should carry for [channel].
  ///
  /// Discord assigns rather than ORs this field, so bit 4 is not preserved by
  /// an ACK — reproducing the assignment keeps our writes identical to the
  /// official client's instead of inventing a merge it never performs.
  static int forChannel(ConversationChannel channel) {
    if (channel.isThread) return thread;
    return channel.spaceId == CommunitySpace.directMessagesId
        ? 0
        : guildChannel;
  }
}

/// One read state: where the account has read up to in a single entity.
final class ReadState {
  ReadState({
    required this.entityId,
    this.type = ReadStateType.channel,
    String? lastAckedId,
    int mentionCount = 0,
    this.flags = 0,
    this.lastViewed,
    this.lastPinTimestamp,
  }) : lastAckedId = _cursor(lastAckedId),
       // Discord has been observed sending a negative badge count for an
       // entity whose mentions were removed faster than they were counted; a
       // negative badge would render as a "-1" pill and sort above real ones.
       mentionCount = mentionCount < 0 ? 0 : mentionCount;

  /// The channel id for [ReadStateType.channel], otherwise the guild or user
  /// id the type is keyed by.
  final String entityId;
  final ReadStateType type;

  /// The newest acknowledged id, or `null` when nothing has been acked.
  ///
  /// Discord spells "nothing" as `0`, as `null`, and by omitting the field;
  /// all three collapse to `null` here so a caller never has to test for the
  /// literal zero that would otherwise compare as a real snowflake.
  final String? lastAckedId;
  final int mentionCount;
  final int flags;

  /// Whole days since the Discord epoch, as last written by a client.
  final int? lastViewed;
  final DateTime? lastPinTimestamp;

  /// R04: the client sets and reads bit 4 to mark a mention it decided was low
  /// importance. Kept so a round trip through this store does not lose it.
  bool get isMentionLowImportance =>
      flags & ReadStateFlags.mentionLowImportance != 0;

  bool get hasMentions => mentionCount > 0;

  /// Whether [lastMessageId] is newer than the ack cursor.
  bool isBehind(String? lastMessageId) {
    if (lastMessageId == null || lastMessageId.isEmpty) return false;
    final acked = lastAckedId;
    if (acked == null) return true;
    return DiscordSnowflake.compare(lastMessageId, acked) > 0;
  }

  ReadState copyWith({
    ReadStateType? type,
    Object? lastAckedId = _keepCursor,
    int? mentionCount,
    int? flags,
    Object? lastViewed = _keepCursor,
    Object? lastPinTimestamp = _keepCursor,
  }) => ReadState(
    entityId: entityId,
    type: type ?? this.type,
    lastAckedId: identical(lastAckedId, _keepCursor)
        ? this.lastAckedId
        : lastAckedId as String?,
    mentionCount: mentionCount ?? this.mentionCount,
    flags: flags ?? this.flags,
    lastViewed: identical(lastViewed, _keepCursor)
        ? this.lastViewed
        : lastViewed as int?,
    lastPinTimestamp: identical(lastPinTimestamp, _keepCursor)
        ? this.lastPinTimestamp
        : lastPinTimestamp as DateTime?,
  );

  /// Moves the cursor forward to [messageId] and clears the badge.
  ///
  /// A rewind is refused: an ACK that raced a newer one must not resurrect
  /// unread messages the account has already seen.
  ReadState acknowledged(String messageId, {int? lastViewed}) {
    final acked = lastAckedId;
    if (acked != null && DiscordSnowflake.compare(messageId, acked) <= 0) {
      return lastViewed == null || lastViewed == this.lastViewed
          ? this
          : copyWith(lastViewed: lastViewed);
    }
    return copyWith(
      lastAckedId: messageId,
      mentionCount: 0,
      lastViewed: lastViewed ?? this.lastViewed,
    );
  }

  /// The key this read state is filed under. Channel read states are keyed by
  /// the bare channel id so a caller holding one can look it up directly;
  /// every other type is namespaced, because two types can name the same guild.
  String get key => keyFor(type, entityId);

  static String keyFor(ReadStateType type, String entityId) =>
      type == ReadStateType.channel ? entityId : '${type.wireValue}:$entityId';

  static const _keepCursor = Object();

  static String? _cursor(String? value) =>
      value == null || value.isEmpty || DiscordSnowflake.isZero(value)
      ? null
      : value;
}

/// The day counter Discord stamps on a channel ACK.
///
/// R04: whole days since the Discord epoch, rounded **up**. The rounding is
/// load-bearing — the server reads it back as the "last viewed" day and a
/// truncating client would report yesterday for most of the day.
int readStateLastViewedFor(DateTime now) {
  final elapsed = now.millisecondsSinceEpoch - DiscordSnowflake.epochMillis;
  if (elapsed <= 0) return 0;
  const millisPerDay = 86400000;
  return (elapsed + millisPerDay - 1) ~/ millisPerDay;
}
