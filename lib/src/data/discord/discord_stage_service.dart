import 'dart:async';

import '../../domain/stage_channel.dart';

/// The REST surface a stage needs.
abstract interface class DiscordStageTransport {
  /// `PATCH /guilds/{guildId}/voice-states/@me`.
  ///
  /// The one route that moves this account between the audience and the
  /// stage: `suppress` decides whether Discord lets it speak, and
  /// `request_to_speak_timestamp` is the raised hand.
  Future<void> patchSelfVoiceState(
    String guildId, {
    required String channelId,
    bool? suppress,
    String? requestToSpeakTimestamp,
    bool clearRequestToSpeak = false,
  });
}

/// Stage instances and this account's standing in them.
///
/// Two stores rather than one: the instance is server state everybody sees,
/// while suppression and the raised hand arrive on this account's own
/// `VOICE_STATE_UPDATE`. Keeping them apart is what lets the room say "nobody
/// is running a stage here" separately from "you are in the audience".
final class DiscordStageService implements StageRepository {
  DiscordStageService(this._transport, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DiscordStageTransport _transport;
  final DateTime Function() _clock;
  final StreamController<String> _updates = StreamController.broadcast();
  final Map<String, StageInstance> _stages = {};
  final Map<String, StagePresence> _presence = {};
  final Map<String, String> _guildByChannel = {};

  String? _currentUserId;

  void setCurrentUserId(String? userId) => _currentUserId = userId;

  @override
  StageInstance? stageFor(String channelId) => _stages[channelId];

  @override
  StagePresence? presenceFor(String channelId) => _presence[channelId];

  @override
  Stream<String> get updates => _updates.stream;

  @override
  Future<void> requestToSpeak(String channelId) async {
    final guildId = _guildFor(channelId);
    if (guildId == null) return;
    // Discord reads the timestamp, not merely its presence: a hand raised
    // "now" is what puts this account at the end of the queue rather than the
    // front of it.
    await _transport.patchSelfVoiceState(
      guildId,
      channelId: channelId,
      requestToSpeakTimestamp: _clock().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> cancelSpeakRequest(String channelId) async {
    final guildId = _guildFor(channelId);
    if (guildId == null) return;
    await _transport.patchSelfVoiceState(
      guildId,
      channelId: channelId,
      clearRequestToSpeak: true,
    );
  }

  @override
  Future<void> setSpeaking(String channelId, {required bool speaking}) async {
    final guildId = _guildFor(channelId);
    if (guildId == null) return;
    // Stepping up clears the hand as well: leaving it raised would show this
    // account queueing for a stage it is already on.
    await _transport.patchSelfVoiceState(
      guildId,
      channelId: channelId,
      suppress: !speaking,
      clearRequestToSpeak: speaking,
    );
  }

  /// Folds a gateway dispatch into the stores.
  ///
  /// Returns the channel that changed, or `null` for an event this service
  /// does not answer for.
  String? accept(String eventName, Map<String, Object?> data) =>
      switch (eventName) {
        'STAGE_INSTANCE_CREATE' ||
        'STAGE_INSTANCE_UPDATE' => _acceptStage(data),
        'STAGE_INSTANCE_DELETE' => _removeStage(data),
        'VOICE_STATE_UPDATE' => _acceptVoiceState(data),
        'GUILD_CREATE' => _acceptGuild(data),
        'READY_SUPPLEMENTAL' => _acceptSupplemental(data),
        _ => null,
      };

  Future<void> close() async {
    if (!_updates.isClosed) await _updates.close();
  }

  String? _acceptStage(Map<String, Object?> data) {
    final stage = readStage(data);
    if (stage == null) return null;
    _stages[stage.channelId] = stage;
    _guildByChannel[stage.channelId] = stage.guildId;
    return _publish(stage.channelId);
  }

  String? _removeStage(Map<String, Object?> data) {
    final channelId = data['channel_id'];
    if (channelId is! String || channelId.isEmpty) return null;
    if (_stages.remove(channelId) == null) return null;
    return _publish(channelId);
  }

  /// Only this account's own voice state matters here: everybody else's
  /// suppression is the roster's business, not the stage controls'.
  String? _acceptVoiceState(Map<String, Object?> data) {
    final userId = data['user_id'];
    final self = _currentUserId;
    if (self == null || userId != self) return null;
    final channelId = data['channel_id'];
    if (channelId is! String || channelId.isEmpty) {
      // A departure: whichever stage this account was in, it is no longer
      // standing anywhere in it.
      final previous = _presence.keys.toList(growable: false);
      _presence.clear();
      for (final id in previous) {
        _publish(id);
      }
      return previous.isEmpty ? null : previous.first;
    }
    final guildId = data['guild_id'];
    if (guildId is String && guildId.isNotEmpty) {
      _guildByChannel[channelId] = guildId;
    }
    _presence[channelId] = StagePresence(
      channelId: channelId,
      isSuppressed: data['suppress'] != false,
      requestedAt: _timestamp(data['request_to_speak_timestamp']),
      isInvited: data['invited_to_speak'] == true,
    );
    return _publish(channelId);
  }

  /// `GUILD_CREATE` carries the stages already running, which is the only way
  /// a client learns about one that started before it connected.
  String? _acceptGuild(Map<String, Object?> data) {
    final guildId = data['id'];
    if (guildId is! String || guildId.isEmpty) return null;
    String? last;
    for (final raw in _objects(data['stage_instances'])) {
      last = _acceptStage({'guild_id': guildId, ...raw}) ?? last;
    }
    for (final raw in _objects(data['channels'])) {
      final channelId = raw['id'];
      if (channelId is String && channelId.isNotEmpty) {
        _guildByChannel[channelId] = guildId;
      }
    }
    return last;
  }

  String? _acceptSupplemental(Map<String, Object?> data) {
    String? last;
    for (final guild in _objects(data['guilds'])) {
      last = _acceptGuild(guild) ?? last;
    }
    return last;
  }

  String? _guildFor(String channelId) => _guildByChannel[channelId];

  String _publish(String channelId) {
    if (!_updates.isClosed) _updates.add(channelId);
    return channelId;
  }

  /// Maps a `StageInstance`, skipping one with no channel.
  static StageInstance? readStage(Map<String, Object?> payload) {
    final channelId = payload['channel_id'];
    final guildId = payload['guild_id'];
    if (channelId is! String || channelId.isEmpty) return null;
    if (guildId is! String || guildId.isEmpty) return null;
    final id = payload['id'];
    return StageInstance(
      id: id is String && id.isNotEmpty ? id : channelId,
      channelId: channelId,
      guildId: guildId,
      topic: payload['topic'] is String ? payload['topic']! as String : '',
      privacyLevel: StagePrivacyLevel.fromWire(payload['privacy_level']),
      // Discord inverted this field: the payload says whether the stage is
      // hidden, and a stage with neither answer is the ordinary listed one.
      isDiscoverable: payload['discoverable_disabled'] != true,
    );
  }

  static DateTime? _timestamp(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  static List<Map<String, Object?>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((entry) => entry.cast<String, Object?>())
            .toList(growable: false)
      : const [];
}
