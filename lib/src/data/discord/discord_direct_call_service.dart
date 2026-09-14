import 'dart:async';

import '../../domain/voice_call.dart';
import 'discord_call_api.dart';
import 'discord_direct_call_store.dart';
import 'discord_gateway_client.dart';
import 'discord_voice_signaling_service.dart';

/// The private-call plane of the desktop-user session.
///
/// Ownership split, deliberately: seats in a call are media state and live with
/// the signalling service beside the guild roster, while the call *record* —
/// who is being rung, whether a ring is even allowed yet — lives here, because
/// only this half needs REST.
final class DiscordDirectCallService implements DirectCallService {
  DiscordDirectCallService({
    required this._api,
    required this._gateway,
    required this._signaling,
    required Stream<DiscordGatewayEvent> events,
    DiscordDirectCallStore? store,
  }) : _store = store ?? DiscordDirectCallStore() {
    _subscription = events.listen(_onGatewayEvent);
  }

  /// R08 observes this literal on the desktop client's ring request.
  static const _analyticsLocation = 'dm_invite';

  final DiscordCallApi _api;
  final DiscordCallGateway _gateway;
  final DiscordVoiceSignalingService _signaling;
  final DiscordDirectCallStore _store;
  final StreamController<VoiceCallEvent> _events = StreamController.broadcast();

  /// Rings that arrived before Discord would accept them, keyed by channel.
  ///
  /// R08: a ring sent before `CALL_CREATE` is rejected, so the desktop client
  /// enqueues it and fires on the create. A null value means "ring everybody",
  /// which is what an empty recipient list means on the wire.
  final Map<String, List<String>?> _queuedRings = {};
  late final StreamSubscription<DiscordGatewayEvent> _subscription;
  String? _currentUserId;
  IncomingCall? _incomingCall;
  bool _closed = false;

  @override
  Stream<VoiceCallEvent> get callEvents => _events.stream;

  @override
  DirectCall? callFor(String channelId) => _store.call(channelId);

  @override
  IncomingCall? get incomingCall => _incomingCall;

  /// Voice-state ownership cannot be decided before the workspace names us, and
  /// neither can "is that ring for me".
  void setCurrentUserId(String userId) {
    _currentUserId = userId;
    _reconcileIncomingCall();
  }

  @override
  void watchChannel(String channelId) {
    if (channelId.isEmpty) return;
    _gateway.connectToCall(channelId);
  }

  @override
  Future<bool> isRingable(String channelId) async {
    try {
      return await _api.isChannelRingable(channelId);
    } on Object {
      // The desktop client treats a failed pre-flight as "you may not ring
      // this person" rather than as an outage, because that is what a DM with
      // a non-friend answers with.
      return false;
    }
  }

  @override
  Future<void> ring(String channelId, {List<String>? recipients}) async {
    final call = _store.call(channelId);
    if (call == null || !call.isRingable) {
      _queuedRings[channelId] = recipients;
      return;
    }
    await _api.ringChannel(
      channelId,
      recipients: recipients,
      analyticsLocation: _analyticsLocation,
    );
  }

  @override
  Future<void> stopRinging(String channelId, {List<String>? recipients}) async {
    // A ring the user has cancelled must not be resurrected by a CALL_CREATE
    // that is still in flight.
    _queuedRings.remove(channelId);
    await _api.stopRingingChannel(channelId, recipients: recipients);
  }

  @override
  Future<void> joinCall({
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) {
    // Joining a channel nobody has subscribed to would leave the client blind
    // to the call it just walked into.
    watchChannel(channelId);
    return _signaling.joinCall(
      channelId: channelId,
      selfMute: selfMute,
      selfDeaf: selfDeaf,
      selfVideo: selfVideo,
    );
  }

  @override
  Future<void> leaveCall(String channelId) => _signaling.leaveCall(channelId);

  void _onGatewayEvent(DiscordGatewayEvent event) {
    if (event is! DiscordGatewayDispatch) return;
    final changes = _store.accept(eventName: event.name, data: event.data);
    for (final change in changes) {
      _emit(change);
      if (change is DirectCallUpdatedEvent) _flushQueuedRing(change.call);
    }
    if (changes.isNotEmpty) _reconcileIncomingCall();
  }

  /// Fires a held ring the moment Discord will accept it.
  ///
  /// R08 records the renderer replacing the recipient list with null here in
  /// nearly every case, which reads as an off-by-sign in the minified source;
  /// the intended semantics are implemented instead — the recipients the caller
  /// asked for, and null only when they asked for everybody.
  void _flushQueuedRing(DirectCall call) {
    if (!call.isRingable) return;
    if (!_queuedRings.containsKey(call.channelId)) return;
    final recipients = _queuedRings.remove(call.channelId);
    unawaited(
      _api
          .ringChannel(
            call.channelId,
            recipients: recipients,
            analyticsLocation: _analyticsLocation,
          )
          .catchError(_ignoreRingFailure),
    );
  }

  void _reconcileIncomingCall() {
    final userId = _currentUserId;
    final next = userId == null ? null : _store.incomingCallFor(userId);
    if (next == _incomingCall) return;
    _incomingCall = next;
    _emit(IncomingCallChangedEvent(next));
  }

  void _emit(VoiceCallEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    _queuedRings.clear();
    _store.clear();
    await _events.close();
  }

  /// A ring that fails after the call already exists is a lost invitation, not
  /// a broken session: the call itself is live and the user can ring again.
  static void _ignoreRingFailure(Object error) {}
}
