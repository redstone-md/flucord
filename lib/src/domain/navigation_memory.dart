/// Where a reader stopped in a channel.
///
/// A message rather than a pixel offset, because rows above it can come and go
/// while the reader is away.
final class ReadingPosition {
  const ReadingPosition({required this.messageId, required this.fromTop});

  /// The first message whose row starts inside the timeline.
  final String messageId;

  /// How far the top of that row sat below the top of the timeline.
  final double fromTop;

  Map<String, Object?> toJson() => {'message': messageId, 'fromTop': fromTop};

  static ReadingPosition? fromJson(Object? json) => switch (json) {
    {'message': final String messageId, 'fromTop': final num fromTop} =>
      ReadingPosition(messageId: messageId, fromTop: fromTop.toDouble()),
    _ => null,
  };
}

/// The saved reading positions, one per channel at most.
///
/// A channel with no position opens as if it were new. A reader at the end of
/// a conversation has no position to come back to.
abstract interface class ReadingPositions {
  ReadingPosition? of(String channelId);

  void keep(String channelId, ReadingPosition? position);
}

/// Everything the app remembers about where an account was.
final class NavigationMemory {
  const NavigationMemory({
    required this.accountId,
    this.lastSpaceId,
    this.lastChannels = const {},
    this.collapsedCategoryIds = const {},
    this.positions = const {},
  });

  /// Whose memory this is. Null in a session with no account to name, as a
  /// demo, whose memory lasts until the app closes and is never saved.
  final String? accountId;
  final String? lastSpaceId;

  /// The last channel open in each space, by space id.
  final Map<String, String> lastChannels;
  final Set<String> collapsedCategoryIds;

  /// By channel id, with the channel read least recently first.
  final Map<String, ReadingPosition> positions;

  /// This memory with the parts given changed, and the account kept.
  NavigationMemory copyWith({
    String? lastSpaceId,
    Map<String, String>? lastChannels,
    Set<String>? collapsedCategoryIds,
    Map<String, ReadingPosition>? positions,
  }) => NavigationMemory(
    accountId: accountId,
    lastSpaceId: lastSpaceId ?? this.lastSpaceId,
    lastChannels: lastChannels ?? this.lastChannels,
    collapsedCategoryIds: collapsedCategoryIds ?? this.collapsedCategoryIds,
    positions: positions ?? this.positions,
  );

  Map<String, Object?> toJson() => {
    'account': accountId,
    'lastSpace': lastSpaceId,
    'lastChannels': lastChannels,
    'collapsedCategories': collapsedCategoryIds.toList(),
    'positions': {
      for (final MapEntry(:key, :value) in positions.entries)
        key: value.toJson(),
    },
  };

  /// What [json] holds, or null when it is not a memory at all. A part that does
  /// not read is left out, since each part has a default.
  static NavigationMemory? fromJson(Object? json) {
    if (json case {'account': final String accountId} && final Map map) {
      return NavigationMemory(
        accountId: accountId,
        lastSpaceId: map['lastSpace'] is String
            ? map['lastSpace'] as String
            : null,
        lastChannels: {
          if (map['lastChannels'] case final Map channels)
            for (final MapEntry(:key, :value) in channels.entries)
              if (key is String && value is String) key: value,
        },
        collapsedCategoryIds: {
          if (map['collapsedCategories'] case final List ids)
            ...ids.whereType<String>(),
        },
        positions: {
          if (map['positions'] case final Map positions)
            for (final MapEntry(:key, :value) in positions.entries)
              if (key is String) key: ?ReadingPosition.fromJson(value),
        },
      );
    }
    return null;
  }
}

/// Where the [NavigationMemory] of the account on this machine is kept.
abstract interface class NavigationMemoryRepository {
  /// The saved memory, or null when there is none or it cannot be read.
  Future<NavigationMemory?> load();

  Future<void> save(NavigationMemory memory);

  Future<void> clear();
}
