import '../../domain/read_state.dart';
import 'discord_read_state_codec.dart';

/// The account's read state as the gateway describes it, held in one place.
///
/// Everything here is a fold over dispatches: `READY` sets the baseline, the
/// ack events, `USER_GUILD_SETTINGS_UPDATE` and the cross-session
/// `STATE_UPDATE` revise it, and `DELETED_ENTITY_IDS` forgets what Discord's
/// garbage collector dropped. The two version counters this keeps are what a
/// later connect echoes back so the server can answer with a delta. The store
/// is deliberately free of transport and of timers: it decides *what is true*,
/// and the repository around it decides what to send.
final class DiscordReadStateStore {
  final Map<String, ReadState> _readStates = {};
  final Map<String, GuildNotificationSettings> _settings = {};
  int _accountNotificationFlags = 0;
  int _readStateVersion = 0;
  int _userGuildSettingsVersion = 0;

  ReadStateSnapshot get snapshot => ReadStateSnapshot(
    readStates: Map.of(_readStates),
    settings: Map.of(_settings),
    accountNotificationFlags: _accountNotificationFlags,
    readStateVersion: _readStateVersion,
    userGuildSettingsVersion: _userGuildSettingsVersion,
  );

  /// Folds one gateway dispatch in. Returns true when anything changed, so the
  /// repository can stay quiet rather than rebuild every unread surface for a
  /// dispatch that told it nothing new.
  bool accept(String name, Map<String, Object?> data) => switch (name) {
    'READY' => _acceptReady(data),
    'STATE_UPDATE' => _acceptStateUpdate(data),
    'DELETED_ENTITY_IDS' => _acceptDeletedEntityIds(data),
    'MESSAGE_ACK' => _acceptMessageAck(data),
    'CHANNEL_PINS_ACK' => _acceptPinsAck(data),
    'CHANNEL_PINS_UPDATE' => _acceptPinsUpdate(data),
    'GUILD_FEATURE_ACK' => _acceptFeatureAck(data),
    'USER_NON_CHANNEL_ACK' => _acceptUserAck(data),
    'USER_GUILD_SETTINGS_UPDATE' => _acceptSettingsUpdate(data),
    _ => false,
  };

  /// Replaces one read state outright, for the optimistic half of an ACK.
  void put(ReadState state) => _readStates[state.key] = state;

  /// Forgets a channel's read state, for the 30-day collector.
  ///
  /// Returns whether there was anything to forget, so a caller that deleted
  /// nothing sends nothing.
  bool removeChannelState(String channelId) =>
      _readStates.remove(channelId) != null;

  /// The read state for [channelId], creating an empty one when the account has
  /// never had a read state there. Discord does the same: a channel with no
  /// stored cursor is acked as if it had one at zero.
  ReadState channelState(String channelId) =>
      _readStates[channelId] ?? ReadState(entityId: channelId);

  ReadState entityState(ReadStateType type, String entityId) =>
      _readStates[ReadState.keyFor(type, entityId)] ??
      ReadState(entityId: entityId, type: type);

  GuildNotificationSettings settingsFor(String spaceId) =>
      _settings[spaceId] ?? GuildNotificationSettings.defaults(spaceId);

  void putSettings(GuildNotificationSettings settings) =>
      _settings[settings.spaceId] = settings;

  void clear() {
    _readStates.clear();
    _settings.clear();
    _accountNotificationFlags = 0;
    _readStateVersion = 0;
    _userGuildSettingsVersion = 0;
  }

  bool _acceptReady(Map<String, Object?> data) {
    _acceptReadStateBlock(data['read_state']);
    _acceptSettingsBlock(data['user_guild_settings']);
    final notifications = data['notification_settings'];
    if (notifications is Map) {
      _accountNotificationFlags = _int(notifications['flags']) ?? 0;
    }
    // READY always rewrites the baseline, even when every block was absent:
    // the surfaces need one emission to leave their pre-connect state.
    return true;
  }

  /// `STATE_UPDATE` carries the same state blocks READY does, and always as a
  /// delta: it exists to sync a change another session made, so the store
  /// merges it over what it holds whether or not the block spells `partial`.
  /// A block that meant to replace everything wholesale would have to name
  /// every entry, and naming every entry is what READY is for.
  bool _acceptStateUpdate(Map<String, Object?> data) {
    final readState = data['read_state'];
    final settings = data['user_guild_settings'];
    if (readState is! Map && settings is! Map) return false;
    if (readState is Map) _mergeReadStateEntries(readState.cast());
    if (settings is Map) _mergeSettingsEntries(settings.cast());
    return true;
  }

  /// `DELETED_ENTITY_IDS` names the read states Discord's own garbage
  /// collector dropped, as one read-state type plus the entity ids of that
  /// type. Forgetting them keeps a collected cursor from showing as unread
  /// forever, since no later dispatch will ever mention the entity again.
  bool _acceptDeletedEntityIds(Map<String, Object?> data) {
    final type = ReadStateType.fromWire(data['read_state_type']);
    if (type == null) return false;
    final ids = _objects(data['ids']).map((entry) => entry['id']).toSet();
    ids.addAll(_strings(data['ids']));
    if (ids.isEmpty) return false;
    var removed = false;
    for (final id in ids.whereType<String>()) {
      if (_readStates.remove(ReadState.keyFor(type, id)) != null) {
        removed = true;
      }
    }
    if (!removed) return false;
    _bumpReadStateVersion(_int(data['version']));
    return true;
  }

  void _acceptReadStateBlock(Object? block) {
    if (block is! Map) return;
    final envelope = block.cast<String, Object?>();
    // R04: `partial: true` is a delta over what we already hold; anything else
    // replaces the lot, including a session whose account read everything
    // elsewhere and now legitimately has no read states at all.
    if (envelope['partial'] != true) _readStates.clear();
    _mergeReadStateEntries(envelope);
  }

  void _mergeReadStateEntries(Map<String, Object?> envelope) {
    for (final entry in _objects(envelope['entries'])) {
      final state = DiscordReadStateCodec.readState(entry);
      if (state != null) _readStates[state.key] = state;
    }
    _bumpReadStateVersion(_int(envelope['version']));
  }

  void _acceptSettingsBlock(Object? block) {
    if (block is! Map) return;
    final envelope = block.cast<String, Object?>();
    if (envelope['partial'] != true) _settings.clear();
    _mergeSettingsEntries(envelope);
  }

  void _mergeSettingsEntries(Map<String, Object?> envelope) {
    for (final entry in _objects(envelope['entries'])) {
      final settings = DiscordReadStateCodec.guildSettings(entry);
      _settings[settings.spaceId] = settings;
    }
    _bumpSettingsVersion(_int(envelope['version']));
  }

  bool _acceptMessageAck(Map<String, Object?> data) {
    final channelId = data['channel_id'];
    final messageId = data['message_id'];
    if (channelId is! String || messageId is! String) return false;
    _bumpReadStateVersion(_int(data['version']));
    final previous = channelState(channelId);
    // A manual ack is a deliberate rewind from another session, so it is the
    // one case where the cursor is allowed to move backwards.
    final next = data['manual'] == true
        ? previous.copyWith(
            lastAckedId: messageId,
            mentionCount: _int(data['mention_count']) ?? 0,
          )
        : previous
              .acknowledged(messageId)
              .copyWith(mentionCount: _int(data['mention_count']) ?? 0);
    _readStates[next.key] = next;
    return true;
  }

  bool _acceptPinsAck(Map<String, Object?> data) {
    final channelId = data['channel_id'];
    if (channelId is! String) return false;
    _bumpReadStateVersion(_int(data['version']));
    final timestamp = data['timestamp'];
    _readStates[channelId] = channelState(channelId).copyWith(
      lastPinTimestamp: timestamp is String
          ? DateTime.tryParse(timestamp)
          : null,
    );
    return true;
  }

  bool _acceptPinsUpdate(Map<String, Object?> data) {
    final channelId = data['channel_id'];
    if (channelId is! String) return false;
    final timestamp = data['last_pin_timestamp'];
    // Only the pointer moves here: a new pin does not acknowledge anything, so
    // the read-state version is deliberately left alone.
    _readStates[channelId] = channelState(channelId).copyWith(
      lastPinTimestamp: timestamp is String
          ? DateTime.tryParse(timestamp)
          : null,
    );
    return true;
  }

  bool _acceptFeatureAck(Map<String, Object?> data) => _acceptEntityAck(
    rawType: data['ack_type'],
    entityId: data['entity_id'] ?? data['resource_id'],
    guildScoped: true,
  );

  bool _acceptUserAck(Map<String, Object?> data) => _acceptEntityAck(
    rawType: data['ack_type'],
    entityId: data['entity_id'],
    guildScoped: false,
  );

  bool _acceptEntityAck({
    required Object? rawType,
    required Object? entityId,
    required bool guildScoped,
  }) {
    final type = ReadStateType.fromWire(rawType);
    if (type == null || entityId is! String || entityId.isEmpty) return false;
    // The two events are not interchangeable: a guild-scoped event naming a
    // user-scoped type (or the reverse) is a payload this client does not
    // understand, and filing it anyway would ack the wrong entity.
    if (guildScoped ? !type.isGuildScoped : !type.isUserScoped) return false;
    final previous = entityState(type, entityId);
    _readStates[previous.key] = previous.copyWith(
      lastAckedId: entityId,
      mentionCount: 0,
    );
    return true;
  }

  bool _acceptSettingsUpdate(Map<String, Object?> data) {
    final settings = DiscordReadStateCodec.guildSettings(data);
    _settings[settings.spaceId] = settings;
    _bumpSettingsVersion(settings.version);
    return true;
  }

  /// R03/R04: the version only ever moves forward. An out-of-order dispatch
  /// carrying an older counter must not walk it back, or the next connect would
  /// ask the server for a delta it has already applied.
  void _bumpReadStateVersion(int? version) {
    if (version != null && version > _readStateVersion) {
      _readStateVersion = version;
    }
  }

  void _bumpSettingsVersion(int? version) {
    if (version != null && version > _userGuildSettingsVersion) {
      _userGuildSettingsVersion = version;
    }
  }

  static int? _int(Object? value) => value is int
      ? value
      : value is num
      ? value.toInt()
      : null;

  static List<Map<String, Object?>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => item.cast<String, Object?>())
            .toList(growable: false)
      : const [];

  static List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];
}
