import '../../domain/voice_call.dart';

/// The client-side mirror of Discord's private-call records.
///
/// `CALL_CREATE` is a whole record and `CALL_UPDATE` a whole record too — R08
/// lists the same four fields on both — so an update replaces rather than
/// patches. `CALL_DELETE` retracts it. Everything the incoming-call surface
/// needs is derived from that one map: `ongoing_rings` answers "is somebody
/// ringing me" and names who, and `message_id` answers "may I ring yet".
final class DiscordDirectCallStore {
  DiscordDirectCallStore({this._maxRings = _defaultMaxRings});

  /// A group DM holds ten people, so a legitimate ring map is tiny. The bound
  /// exists because the count arrives on the wire and drives an allocation.
  static const _defaultMaxRings = 256;

  final int _maxRings;
  final Map<String, DirectCall> _calls = {};

  DirectCall? call(String channelId) => _calls[channelId];

  /// Folds one dispatch in, returning what changed.
  ///
  /// A dispatch that changes nothing returns an empty list, so a repeated
  /// `CALL_UPDATE` cannot make the surface flicker.
  List<VoiceCallEvent> accept({
    required String eventName,
    required Map<String, Object?> data,
  }) => switch (eventName) {
    'CALL_CREATE' || 'CALL_UPDATE' => _upsert(data),
    'CALL_DELETE' => _delete(data),
    // A replayed READY invalidates every record: the subscriptions that
    // produced them died with the session, and the client re-subscribes.
    'READY' => _clearAll(),
    _ => const [],
  };

  /// Who is ringing [userId] right now, across every known call.
  IncomingCall? incomingCallFor(String userId) {
    for (final call in _calls.values) {
      if (call.unavailable) continue;
      final callerId = call.callerFor(userId);
      if (callerId != null && callerId.isNotEmpty) {
        return IncomingCall(channelId: call.channelId, callerId: callerId);
      }
    }
    return null;
  }

  void clear() => _calls.clear();

  List<VoiceCallEvent> _upsert(Map<String, Object?> data) {
    final channelId = data['channel_id'];
    if (channelId is! String || channelId.isEmpty) return const [];
    final call = DirectCall(
      channelId: channelId,
      messageId: _string(data['message_id']),
      region: _string(data['region']),
      ongoingRings: _rings(data['ongoing_rings']),
      unavailable: data['unavailable'] == true,
    );
    final previous = _calls[channelId];
    if (previous != null && _same(previous, call)) return const [];
    _calls[channelId] = call;
    return [DirectCallUpdatedEvent(call)];
  }

  List<VoiceCallEvent> _delete(Map<String, Object?> data) {
    final channelId = data['channel_id'];
    if (channelId is! String) return const [];
    // `unavailable: true` is Discord saying the call is temporarily out of
    // reach rather than over. Keeping the record — flagged — is what stops the
    // client from offering a ring that would be rejected.
    if (data['unavailable'] == true) {
      final existing = _calls[channelId];
      if (existing == null || existing.unavailable) return const [];
      final updated = existing.markUnavailable();
      _calls[channelId] = updated;
      return [DirectCallUpdatedEvent(updated)];
    }
    if (_calls.remove(channelId) == null) return const [];
    return [DirectCallEndedEvent(channelId)];
  }

  List<VoiceCallEvent> _clearAll() {
    if (_calls.isEmpty) return const [];
    final ended = [
      for (final channelId in _calls.keys) DirectCallEndedEvent(channelId),
    ];
    _calls.clear();
    return ended;
  }

  Map<String, String> _rings(Object? value) {
    if (value is! Map) return const {};
    final rings = <String, String>{};
    for (final entry in value.entries) {
      if (rings.length >= _maxRings) break;
      final recipient = entry.key;
      final caller = entry.value;
      // R08: the map is recipient -> caller, and a null value means the entry
      // is stale rather than an active ring.
      if (recipient is! String || recipient.isEmpty) continue;
      if (caller is! String || caller.isEmpty) continue;
      rings[recipient] = caller;
    }
    return Map.unmodifiable(rings);
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static bool _same(DirectCall left, DirectCall right) =>
      left.messageId == right.messageId &&
      left.region == right.region &&
      left.unavailable == right.unavailable &&
      _sameRings(left.ongoingRings, right.ongoingRings);

  static bool _sameRings(Map<String, String> left, Map<String, String> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }
}
