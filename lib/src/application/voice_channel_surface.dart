/// The two things a voice channel can show. Discord hangs an ordinary message
/// timeline off the same channel id as the room, so "which voice channel is
/// selected" is not enough to decide what to render — the surface is a second,
/// independent axis of the selection.
enum VoiceChannelSurface { room, chat }

/// Remembers, per voice channel, which surface was last shown.
///
/// The surface is view state: no repository ever reports it and nothing is
/// persisted, so it lives beside the rest of the workspace selection instead of
/// on [ConversationChannel]. Keeping it per channel rather than as one global
/// flag means walking away from a channel and coming back does not silently
/// drop the user on the other side of the switch; pruning against the live
/// channel set keeps a long session from accumulating an entry for every
/// channel the workspace has ever held.
final class VoiceChannelSurfaces {
  final Map<String, VoiceChannelSurface> _surfaces = {};

  /// The room is the default because picking a voice channel out of the channel
  /// sidebar is the "walk into the room" gesture. Message-shaped navigation —
  /// a channel mention, the quick switcher, the inbox — asks for
  /// [VoiceChannelSurface.chat] explicitly rather than inheriting it.
  VoiceChannelSurface of(String channelId) =>
      _surfaces[channelId] ?? VoiceChannelSurface.room;

  /// Returns whether the stored surface actually moved, so callers can decide
  /// whether a rebuild is warranted.
  bool select(String channelId, VoiceChannelSurface surface) {
    if (of(channelId) == surface) return false;
    _surfaces[channelId] = surface;
    return true;
  }

  void retainAll(Iterable<String> channelIds) {
    final retained = channelIds.toSet();
    _surfaces.removeWhere((channelId, _) => !retained.contains(channelId));
  }
}
