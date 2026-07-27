import 'chat_models.dart';
import 'guild_audit_log.dart';
import 'guild_management.dart';

/// Everything a server-settings surface needs from the server.
///
/// Stated as one contract rather than six because the surface is one window:
/// a transport either holds a Discord session that may administer guilds or it
/// does not, and splitting the answer per section would let a caller show four
/// tabs that work and two that fail on open.
///
/// Nothing here is permission-aware. Whether the account *may* run one of these
/// is a computed-permission question the caller answers before it asks, using
/// `WorkspacePermissions`; a repository that re-derived it would need the
/// workspace, and two places deciding would eventually disagree.
abstract interface class GuildManagementRepository {
  Future<GuildOverviewSettings> loadGuildOverview(String guildId);

  Future<GuildOverviewSettings> saveGuildOverview({
    required String guildId,
    required GuildOverviewPatch patch,
  });

  Future<List<GuildRole>> loadRoles(String guildId);

  Future<GuildRole> createRole({
    required String guildId,
    required GuildRoleDraft draft,
  });

  Future<GuildRole> updateRole({
    required String guildId,
    required String roleId,
    required GuildRoleEdit edit,
  });

  Future<void> deleteRole({required String guildId, required String roleId});

  /// Applies a whole reorder in one request, as Discord's roles page does.
  Future<void> reorderRoles({
    required String guildId,
    required List<RolePositionDelta> deltas,
  });

  Future<ConversationChannel> createGuildChannel({
    required String guildId,
    required GuildChannelDraft draft,
  });

  Future<ConversationChannel> editGuildChannel({
    required String channelId,
    required GuildChannelEdit edit,
  });

  Future<void> deleteGuildChannel(String channelId);

  Future<void> reorderGuildChannels({
    required String guildId,
    required List<ChannelPositionDelta> deltas,
  });

  /// One page of bans, newest ids last. [after] is the previous page's last
  /// user id.
  Future<List<GuildBan>> loadBans({
    required String guildId,
    int limit = 1000,
    String? after,
  });

  Future<List<GuildBan>> searchBans({
    required String guildId,
    required String query,
    int limit = 10,
  });

  /// Bans one member, or several in a single bulk request.
  Future<BulkBanResult> banMembers({
    required String guildId,
    required BanRequest request,
  });

  Future<void> unbanMember({
    required String guildId,
    required String userId,
    String? reason,
  });

  Future<void> kickMember({
    required String guildId,
    required String userId,
    String? reason,
  });

  Future<List<GuildInvite>> loadGuildInvites(String guildId);

  Future<GuildInvite> createChannelInvite({
    required String channelId,
    InviteOptions options,
  });

  Future<void> revokeInvite(String code);

  Future<AuditLogPage> loadAuditLog({
    required String guildId,
    AuditLogQuery query,
  });
}
