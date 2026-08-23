/// Rules both Discord gateways follow: the main gateway and the voice one.
///
/// Written once here because they were once written twice, and the copies
/// were already drifting apart when that was found.
library;

/// Counts heartbeats the server has not answered.
///
/// Both gateways run the same policy: a heartbeat or two can go unanswered
/// on a slow network, and past that the session is dead. What happens then
/// differs per gateway, so each protocol decides that itself; this class
/// only owns the count and the threshold.
final class DiscordGatewayHeartbeatWatchdog {
  /// How many heartbeats may go unanswered before the session is written
  /// off.
  ///
  /// One is too few. An acknowledgement that arrives a moment after the
  /// next interval is a slow network, not a dead socket, and tearing the
  /// connection down for it costs more than the wait: the voice gateway
  /// answers the redial with `sessionInvalid` and the call spends its life
  /// reconnecting, and a reconnect on the main gateway ends every voice
  /// call downstream, because each voice session is identified with that
  /// gateway session's id.
  static const tolerance = 2;

  int _unacknowledged = 0;

  /// How many sent heartbeats are still waiting for an answer.
  int get unacknowledgedCount => _unacknowledged;

  /// The server answered. Whatever was in flight is settled.
  void acknowledge() => _unacknowledged = 0;

  /// Another heartbeat went out and is now waiting.
  void recordSent() => _unacknowledged++;

  /// Whether the count has passed [tolerance] and the session is dead.
  bool get hasExceededTolerance => _unacknowledged >= tolerance;
}

/// Close codes shared by Discord's gateways.
///
/// Most close codes mean different things on different gateways; only the
/// ones that mean the same everywhere live here.
abstract final class DiscordGatewayCloseCodes {
  /// Authentication failed.
  ///
  /// No gateway redials through this: the credential itself was rejected,
  /// and reconnecting would only collect the same answer.
  static const authenticationFailed = 4004;
}
