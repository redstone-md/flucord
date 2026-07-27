import 'dart:async';

import '../../domain/chat_models.dart';
import '../../domain/presence_repository.dart';
import '../../domain/user_settings.dart';
import '../../domain/user_settings_repository.dart';
import 'discord_desktop_gateway_protocol.dart';
import 'discord_idle_tracker.dart';
import 'discord_presence_mapper.dart';
import 'discord_presence_store.dart';
import 'discord_presence_updater.dart';
import 'discord_self_presence.dart';

/// The presence plane of the desktop-user transport.
///
/// It owns both directions at once because they are one loop: the account's
/// stored status and the idle machine compose what goes out on opcode 3, and
/// the very same status has to be written back into this client's own member
/// row — R07 is explicit that the server never echoes the account's presence
/// back, so a client that only listened would show itself permanently offline.
final class DiscordPresenceService implements PresenceService {
  DiscordPresenceService({
    required void Function(Map<String, Object?> payload) sendPresence,
    required bool Function() isSessionEstablished,
    UserSettingsRepository? settings,
    DateTime Function()? clock,
    DiscordPresenceTimerFactory? timerFactory,
    this._idlePollInterval = const Duration(seconds: 30),
  }) : _settings = settings,
       _clock = clock ?? DateTime.now {
    _idle = DiscordIdleTracker(startedAt: _clock());
    _updater = DiscordPresenceUpdater(
      send: sendPresence,
      isSessionEstablished: isSessionEstablished,
      clock: _clock,
      timerFactory: timerFactory,
    );
    _settingsSubscription = settings?.updates.listen(_acceptSettings);
    if (settings?.current case final current?) _stored = current;
    _recompose();
    _startIdlePolling();
  }

  final UserSettingsRepository? _settings;
  final DateTime Function() _clock;
  final Duration? _idlePollInterval;
  final DiscordPresenceStore _store = DiscordPresenceStore();
  final StreamController<SelfPresence> _selfUpdates =
      StreamController.broadcast();

  late final DiscordIdleTracker _idle;
  late final DiscordPresenceUpdater _updater;
  StreamSubscription<UserSettings>? _settingsSubscription;
  Timer? _idleTimer;

  UserSettings? _stored;
  SelfPresence _self = const SelfPresence();
  List<UserSession> _sessions = const [];
  String? _currentUserId;

  /// The inbound presence map, for surfaces that need a user this client has
  /// no member row for yet.
  DiscordPresenceStore get store => _store;

  @override
  SelfPresence get selfPresence => _self;

  @override
  Presence get chosenStatus {
    final stored = _stored?.status.status;
    if (stored == null || stored.isEmpty) return Presence.online;
    final parsed = Presence.fromWire(stored);
    return parsed == Presence.unknown ? Presence.online : parsed;
  }

  @override
  UserActivity? get customStatus {
    final stored = _stored?.status;
    if (stored == null) return null;
    return DiscordSelfPresence.customStatus(stored, now: _clock());
  }

  @override
  List<UserSession> get sessions => _sessions;

  @override
  Stream<SelfPresence> get selfPresenceUpdates => _selfUpdates.stream;

  @override
  bool get canEdit => _settings?.isLoaded ?? false;

  @override
  Future<void> setStatus(Presence status) async {
    final settings = _settings;
    if (settings == null || !Presence.selectable.contains(status)) return;
    await settings.apply(UserSettingsPatch(onlineStatus: status));
  }

  @override
  Future<void> setCustomStatus({
    String text = '',
    String emojiName = '',
    CustomStatusDuration expiry = CustomStatusDuration.never,
  }) async {
    final settings = _settings;
    if (settings == null) return;
    if (text.isEmpty && emojiName.isEmpty) {
      await settings.apply(const UserSettingsPatch(clearCustomStatus: true));
      return;
    }
    await settings.apply(
      UserSettingsPatch(
        customStatusText: text,
        customStatusEmojiName: emojiName,
        customStatusExpiresAtMs: expiry.expiryAt(_clock()),
      ),
    );
  }

  @override
  void markActive() {
    if (_idle.markActive(_clock())) _recompose();
  }

  /// The account this client is signed in as. Its presence never comes from
  /// the inbound map.
  set currentUserId(String? value) {
    _currentUserId = value;
    _store.currentUserId = value;
  }

  String? get currentUserId => _currentUserId;

  /// Applies one gateway dispatch, returning the presences it changed.
  ///
  /// The account's own entry is included so the caller can update its member
  /// row from the same batch every other user arrives in.
  Map<String, UserPresence> accept(String name, Map<String, Object?> data) {
    switch (name) {
      case 'READY':
        return _acceptReady(data);
      case 'READY_SUPPLEMENTAL':
        return _acceptSupplemental(data);
      case 'RESUMED':
        _updater.forceUpdate();
        return const {};
      case 'PRESENCE_UPDATE':
        final record = DiscordPresenceMapper.record(data);
        return record == null ? const {} : _store.apply([record]);
      case 'PRESENCES_REPLACE':
        return _store.replaceFriendScope(
          DiscordPresenceMapper.records(_arrayOf(data)),
        );
      case 'SESSIONS_REPLACE':
        _sessions = DiscordPresenceMapper.sessions(_arrayOf(data));
        _publishSelf();
        return const {};
      case 'GUILD_CREATE':
        final guildId = data['id'];
        if (guildId is! String) return const {};
        return _store.apply(
          DiscordPresenceMapper.records(data['presences'], guildId: guildId),
        );
      case 'GUILD_DELETE':
        final guildId = data['id'];
        return guildId is String ? _store.removeGuild(guildId) : const {};
      case 'GUILD_MEMBER_REMOVE':
        return _acceptMemberRemove(data);
      case 'GUILD_MEMBERS_CHUNK':
        final guildId = data['guild_id'];
        if (guildId is! String) return const {};
        return _store.apply(
          DiscordPresenceMapper.records(data['presences'], guildId: guildId),
        );
      case 'GUILD_MEMBER_LIST_UPDATE':
        return _acceptMemberList(data);
      default:
        return const {};
    }
  }

  /// The gateway session came up. Anything the updater held back goes now.
  void sessionEstablished() => _updater.sessionEstablished();

  Future<void> close() async {
    _idleTimer?.cancel();
    _updater.dispose();
    await _settingsSubscription?.cancel();
    await _selfUpdates.close();
  }

  Map<String, UserPresence> _acceptReady(Map<String, Object?> data) {
    _store.clear();
    _updater.reset();
    final user = data['user'];
    if (user is Map && user['id'] is String) {
      currentUserId = user['id']! as String;
    }
    _sessions = DiscordPresenceMapper.sessions(data['sessions']);
    _recompose();
    return const {};
  }

  /// R03 establishes `merged_presences.guilds[i]` as index-aligned with
  /// `READY_SUPPLEMENTAL.guilds`, and `merged_presences.friends` as the
  /// guild-less scope, so both arms can be attributed without guessing.
  Map<String, UserPresence> _acceptSupplemental(Map<String, Object?> data) {
    final merged = data['merged_presences'];
    if (merged is! Map) return const {};
    final records = <DiscordPresenceRecord>[
      ...DiscordPresenceMapper.records(merged['friends']),
    ];
    final guilds = data['guilds'];
    final byGuild = merged['guilds'];
    if (guilds is List && byGuild is List) {
      for (var index = 0; index < guilds.length; index++) {
        if (index >= byGuild.length) break;
        final guild = guilds[index];
        final guildId = guild is Map ? guild['id'] : null;
        if (guildId is! String) continue;
        records.addAll(
          DiscordPresenceMapper.records(byGuild[index], guildId: guildId),
        );
      }
    }
    return _store.apply(records);
  }

  Map<String, UserPresence> _acceptMemberRemove(Map<String, Object?> data) {
    final guildId = data['guild_id'];
    final user = data['user'];
    final userId = user is Map ? user['id'] : null;
    if (guildId is! String || userId is! String) return const {};
    return _store.removeMember(guildId: guildId, userId: userId);
  }

  /// A lazy member list carries each row's presence inside its member item,
  /// which on this transport is the first place most guild presences appear.
  Map<String, UserPresence> _acceptMemberList(Map<String, Object?> data) {
    final guildId = data['guild_id'];
    if (guildId is! String) return const {};
    final operations = data['ops'];
    if (operations is! List) return const {};
    final records = <DiscordPresenceRecord>[];
    for (final operation in operations.whereType<Map>()) {
      _collectListItem(operation['item'], guildId, records);
      final items = operation['items'];
      if (items is List) {
        for (final item in items) {
          _collectListItem(item, guildId, records);
        }
      }
    }
    return records.isEmpty ? const {} : _store.apply(records);
  }

  static void _collectListItem(
    Object? item,
    String guildId,
    List<DiscordPresenceRecord> into,
  ) {
    if (item is! Map) return;
    final member = item['member'];
    if (member is! Map) return;
    final presence = member['presence'];
    if (presence is! Map) return;
    final payload = presence.cast<String, Object?>();
    // The presence rides inside the member item, so the user it belongs to is
    // on the member rather than on the presence itself.
    final user = payload['user'] ?? member['user'];
    final record = DiscordPresenceMapper.record({
      ...payload,
      'user': ?user,
    }, guildId: guildId);
    if (record != null) into.add(record);
  }

  static Object? _arrayOf(Map<String, Object?> data) =>
      data[DiscordDesktopGatewayDispatch.arrayPayloadKey];

  void _acceptSettings(UserSettings settings) {
    _stored = settings;
    _idle.setAfkTimeoutSeconds(
      settings.voiceAndVideo.afkTimeout,
      now: _clock(),
    );
    _recompose();
  }

  void _recompose() {
    _self = DiscordSelfPresence.compose(
      now: _clock(),
      stored: _stored?.status,
      idleSince: _idle.idleSince,
      afk: _idle.isAfk,
    );
    _updater.update(_self);
    _publishSelf();
  }

  void _publishSelf() {
    if (!_selfUpdates.isClosed) _selfUpdates.add(_self);
  }

  void _startIdlePolling() {
    final interval = _idlePollInterval;
    if (interval == null) return;
    _idleTimer = Timer.periodic(interval, (_) => evaluateIdle());
  }

  /// Re-reads the idle machine. Public so a host without a periodic timer —
  /// a test, or a platform that learns about system idle directly — can drive
  /// it on its own schedule.
  void evaluateIdle() {
    final idleChanged = _idle.evaluate(_clock());
    // A custom status with an expiry stops being true on its own, with no event
    // to announce it. Composition already honours the deadline, but nothing was
    // recomposing once it passed, so an expired status kept being broadcast in
    // the opcode-3 payload and kept showing on the account's own row. The idle
    // tick is the one thing that fires regardless, so it checks for that too.
    if (idleChanged || _customStatusExpired()) _recompose();
  }

  /// Whether the account's own presence still carries a custom status that its
  /// own expiry has already passed.
  bool _customStatusExpired() {
    final present = _self.activities.any(
      (activity) => activity.name == DiscordSelfPresence.customStatusName,
    );
    if (!present) return false;
    final stored = _stored?.status;
    if (stored == null) return false;
    return DiscordSelfPresence.customStatus(stored, now: _clock()) == null;
  }

  /// The presence this client publishes for its own row, which is composed
  /// locally rather than received.
  UserPresence get selfUserPresence => UserPresence(
    status: _self.status,
    clientStatus: {ClientPlatform.desktop: _self.status},
    activities: _self.activities,
  );
}
