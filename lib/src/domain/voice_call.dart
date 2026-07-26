/// A live call in a DM or group DM.
///
/// Discord does not model a private call as a channel property: the channel
/// exists whether or not anyone is calling, and the call is a separate record
/// the gateway pushes as `CALL_CREATE` / `CALL_UPDATE` and retracts as
/// `CALL_DELETE`. Nothing arrives until the client has subscribed to that
/// channel with opcode 13, so the absence of a record means "not subscribed or
/// nobody is calling", never "the channel cannot be called".
final class DirectCall {
  const DirectCall({
    required this.channelId,
    this.messageId,
    this.region,
    this.ongoingRings = const {},
    this.unavailable = false,
  });

  final String channelId;

  /// The call's system message. Discord will not accept a ring until this
  /// exists, which is why it is the gate on [isRingable].
  final String? messageId;
  final String? region;

  /// Keyed by the *recipient* being rung, valued with the *caller* who rang
  /// them. R08 is explicit about that direction, and getting it backwards would
  /// name the wrong person on every incoming-call surface.
  final Map<String, String> ongoingRings;
  final bool unavailable;

  /// Everyone currently being rung.
  Iterable<String> get ringing => ongoingRings.keys;

  /// Whether Discord will accept a ring for this call right now.
  ///
  /// R08's gate for channel types 1 and 3 is "a call record exists with a
  /// message id and is not marked unavailable". A ring sent before that is
  /// rejected, so callers enqueue instead.
  bool get isRingable => messageId != null && !unavailable;

  /// Who is ringing [userId], or null when they are not being rung.
  String? callerFor(String userId) => ongoingRings[userId];

  /// The same call, flagged as temporarily out of reach.
  ///
  /// Discord retracts a call it cannot currently serve with `CALL_DELETE` and
  /// `unavailable: true`, which is not the same as the call being over — the
  /// record survives so a ring is not offered while it would be rejected.
  DirectCall markUnavailable() => DirectCall(
    channelId: channelId,
    messageId: messageId,
    region: region,
    ongoingRings: ongoingRings,
    unavailable: true,
  );
}

/// A call the local user is being rung for.
final class IncomingCall {
  const IncomingCall({required this.channelId, required this.callerId});

  final String channelId;
  final String callerId;

  @override
  bool operator ==(Object other) =>
      other is IncomingCall &&
      other.channelId == channelId &&
      other.callerId == callerId;

  @override
  int get hashCode => Object.hash(channelId, callerId);
}

sealed class VoiceCallEvent {
  const VoiceCallEvent();
}

final class DirectCallUpdatedEvent extends VoiceCallEvent {
  const DirectCallUpdatedEvent(this.call);

  final DirectCall call;
}

final class DirectCallEndedEvent extends VoiceCallEvent {
  const DirectCallEndedEvent(this.channelId);

  final String channelId;
}

/// Emitted whenever the answer to "is somebody ringing me" changes, including
/// the transition back to null when the ring stops.
final class IncomingCallChangedEvent extends VoiceCallEvent {
  const IncomingCallChangedEvent(this.call);

  final IncomingCall? call;
}

/// The private-call plane of a transport.
///
/// Kept apart from `VoiceSignalingService` because the two are separate
/// capabilities of a transport rather than two halves of one: a bot session can
/// hold guild voice and can never place a DM call, and an offline session has
/// neither. A transport that cannot ring says so by returning null from
/// `ChatRepository.directCalls`, which is a better answer than a caller
/// guessing from the repository's runtime type.
abstract interface class DirectCallService {
  Stream<VoiceCallEvent> get callEvents;

  /// The live record for [channelId], or null when there is no call.
  DirectCall? callFor(String channelId);

  /// The call ringing the local user right now, if any.
  IncomingCall? get incomingCall;

  /// Subscribes to a private channel's call (gateway opcode 13).
  ///
  /// Discord pushes `CALL_CREATE` only to subscribers, so a channel nobody has
  /// watched looks permanently call-free.
  void watchChannel(String channelId);

  /// Whether Discord will let the local user ring [channelId] at all.
  ///
  /// The pre-flight matters for a DM with a non-friend: the ring itself would
  /// be rejected, and the desktop client shows an "add as a friend" prompt
  /// instead of failing silently.
  Future<bool> isRingable(String channelId);

  /// Rings [recipients], or everybody in the channel when it is null.
  ///
  /// Rings placed before the call record exists are held and fired the moment
  /// `CALL_CREATE` lands, because Discord rejects an early ring.
  Future<void> ring(String channelId, {List<String>? recipients});

  /// Stops ringing [recipients], or — with no recipients — declines the ring
  /// aimed at the local user.
  Future<void> stopRinging(String channelId, {List<String>? recipients});

  /// Connects the media plane to a private call.
  Future<void> joinCall({
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
  });

  Future<void> leaveCall(String channelId);
}
