/// A live stage, as Discord's `StageInstance` describes it.
///
/// A stage channel can exist without one: the instance is the event that is
/// running in it right now, which is why the topic and the audience rules live
/// here rather than on the channel.
final class StageInstance {
  const StageInstance({
    required this.id,
    required this.channelId,
    required this.guildId,
    this.topic = '',
    this.privacyLevel = StagePrivacyLevel.guildOnly,
    this.isDiscoverable = false,
  });

  final String id;
  final String channelId;
  final String guildId;
  final String topic;
  final StagePrivacyLevel privacyLevel;

  /// Whether the stage is listed outside the server.
  final bool isDiscoverable;

  @override
  bool operator ==(Object other) =>
      other is StageInstance &&
      other.id == id &&
      other.channelId == channelId &&
      other.guildId == guildId &&
      other.topic == topic &&
      other.privacyLevel == privacyLevel &&
      other.isDiscoverable == isDiscoverable;

  @override
  int get hashCode =>
      Object.hash(id, channelId, guildId, topic, privacyLevel, isDiscoverable);
}

/// `StageInstance.privacy_level`, as Discord numbers it.
enum StagePrivacyLevel {
  /// Visible to anybody who can find the server. Discord retired this value
  /// but still sends it for stages created before it went away.
  public(1),

  guildOnly(2);

  const StagePrivacyLevel(this.wireValue);

  final int wireValue;

  static StagePrivacyLevel fromWire(Object? value) => switch (value) {
    1 => StagePrivacyLevel.public,
    _ => StagePrivacyLevel.guildOnly,
  };
}

/// Where this account stands in a stage.
enum StageRole {
  /// Listening, and not asking to speak.
  audience,

  /// Listening, with a raised hand Discord is showing to the moderators.
  requestedToSpeak,

  /// Invited to speak but not yet accepted: Discord clears `suppress` only
  /// once the invitation is taken up.
  invitedToSpeak,

  /// On stage and audible.
  speaker,
}

/// This account's own stage voice state.
final class StagePresence {
  const StagePresence({
    required this.channelId,
    this.isSuppressed = true,
    this.requestedAt,
    this.isInvited = false,
  });

  final String channelId;

  /// Whether Discord is muting this account because it is in the audience.
  final bool isSuppressed;

  /// When the hand went up, or `null` when it is down.
  final DateTime? requestedAt;

  /// Whether a moderator invited this account to speak.
  final bool isInvited;

  StageRole get role {
    if (!isSuppressed) return StageRole.speaker;
    if (isInvited) return StageRole.invitedToSpeak;
    return requestedAt == null
        ? StageRole.audience
        : StageRole.requestedToSpeak;
  }
}

/// Reading a stage and taking part in it.
abstract interface class StageRepository {
  /// The stage running in [channelId], or `null` when none is.
  StageInstance? stageFor(String channelId);

  /// This account's standing in [channelId].
  StagePresence? presenceFor(String channelId);

  /// Fires whenever any stage or this account's standing in one changes.
  Stream<String> get updates;

  /// Raises this account's hand.
  Future<void> requestToSpeak(String channelId);

  /// Lowers it again, staying in the audience.
  Future<void> cancelSpeakRequest(String channelId);

  /// Accepts an invitation, or steps back down when [speaking] is false.
  Future<void> setSpeaking(String channelId, {required bool speaking});
}
