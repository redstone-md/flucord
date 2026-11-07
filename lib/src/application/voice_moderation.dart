import '../domain/chat_models.dart';
import '../domain/guild_management.dart';
import '../domain/guild_management_repository.dart';
import '../domain/voice_connection.dart';
import '../domain/workspace_permissions.dart';

/// What a voice moderator may do to people seated in a guild's voice
/// channels, judged by this account's permissions in each channel.
///
/// Every action is one `PATCH /guilds/{id}/members/{user}`. Nothing changes
/// here when it succeeds: Discord answers with a voice state, and the tiles
/// and seats follow that.
final class VoiceModeration {
  const VoiceModeration({
    required GuildManagementRepository members,
    required WorkspacePermissions permissions,
  }) : _members = members,
       _permissions = permissions;

  final GuildManagementRepository _members;
  final WorkspacePermissions _permissions;

  /// What this account may do to whoever holds [seat]. Null for a seat
  /// outside a guild voice channel this account can see, and in a guild
  /// whose permissions this client was never told: channel permissions read
  /// that gap as full, which must not offer moderation to anyone.
  ///
  /// Stage channels are voice channels here too, so Move to lists them.
  ParticipantModeration? of(VoiceParticipantStateEvent seat) {
    final guildId = seat.guildId;
    if (guildId == null || _permissions.inSpace(guildId) == null) return null;
    final channels = _permissions.visibleChannelsFor(guildId);
    final room = channels.where((c) => c.id == seat.channelId).firstOrNull;
    if (room == null) return null;
    final rights = _permissions.capabilitiesIn(room);
    return ParticipantModeration._(
      members: _members,
      seat: seat,
      guildId: guildId,
      canMute: rights.muteMembers,
      canDeafen: rights.deafenMembers,
      canDisconnect: rights.moveMembers,
      moveTargets: rights.moveMembers
          ? [
              for (final channel in channels)
                if (channel.kind == ChannelKind.voice &&
                    channel.id != room.id &&
                    _canMoveInto(channel))
                  channel,
            ]
          : const [],
    );
  }

  bool _canMoveInto(ConversationChannel channel) {
    final rights = _permissions.capabilitiesIn(channel);
    return rights.connect && rights.moveMembers;
  }
}

/// The moderation rows for one seated participant, and the requests behind
/// them.
final class ParticipantModeration {
  const ParticipantModeration._({
    required GuildManagementRepository members,
    required VoiceParticipantStateEvent seat,
    required String guildId,
    required this.canMute,
    required this.canDeafen,
    required this.canDisconnect,
    required this.moveTargets,
  }) : _members = members,
       _seat = seat,
       _guildId = guildId;

  final GuildManagementRepository _members;
  final VoiceParticipantStateEvent _seat;
  final String _guildId;

  final bool canMute;
  final bool canDeafen;
  final bool canDisconnect;

  /// The other voice channels of the guild the participant may be moved to,
  /// in sidebar order. Empty when they cannot be moved.
  final List<ConversationChannel> moveTargets;

  bool get isEmpty =>
      !canMute && !canDeafen && !canDisconnect && moveTargets.isEmpty;

  bool get isServerMuted => _seat.serverMuted;
  bool get isServerDeafened => _seat.serverDeafened;

  Future<void> setServerMuted(bool muted) =>
      _patch(GuildMemberEdit()..serverMuted = muted);

  Future<void> setServerDeafened(bool deafened) =>
      _patch(GuildMemberEdit()..serverDeafened = deafened);

  Future<void> moveTo(String channelId) =>
      _patch(GuildMemberEdit()..voiceChannelId = channelId);

  Future<void> disconnect() => _patch(GuildMemberEdit()..voiceChannelId = null);

  Future<void> _patch(GuildMemberEdit edit) => _members.updateMember(
    guildId: _guildId,
    userId: _seat.userId,
    edit: edit,
  );
}
