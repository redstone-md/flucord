import '../domain/chat_models.dart';

/// The two things a voice channel can show. Discord hangs an ordinary message
/// timeline off the same channel id as the room, so "which voice channel is
/// selected" is not enough to decide what to render: the surface is a second,
/// independent axis of the selection.
enum VoiceChannelSurface { room, chat }

/// Whether [channel] draws its message timeline rather than the room.
///
/// A voice channel only behaves like a text channel while its chat surface is
/// the one on screen: the room has no timeline to search, pin, or type into.
/// Forum and media channels never qualify, because their messages live in
/// posts.
///
/// A DM in a call earns the same two surfaces for the same reason. The call is
/// a room hanging off a channel that also has a timeline, which is exactly the
/// shape a voice channel has, so it reuses this rule rather than inventing a
/// second way to say "show me the room".
bool showsMessageTimeline(
  ConversationChannel channel,
  VoiceChannelSurface voiceSurface, {
  bool inCall = false,
}) =>
    channel.hasMessageTimeline &&
    ((channel.kind != ChannelKind.voice && !inCall) ||
        voiceSurface == VoiceChannelSurface.chat);

/// Whether [channel] shows the room-or-chat switch at all.
bool hasVoiceSurfaces(ConversationChannel channel, {required bool inCall}) =>
    channel.kind == ChannelKind.voice || inCall;

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
