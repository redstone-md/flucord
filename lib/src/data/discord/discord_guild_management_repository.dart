import '../../domain/chat_models.dart';
import '../../domain/guild_audit_log.dart';
import '../../domain/guild_management.dart';
import '../../domain/guild_management_repository.dart';
import 'discord_guild_admin_mapper.dart';
import 'discord_mapper.dart';
import 'discord_rest_client.dart';

part 'discord_guild_management_channels.dart';
part 'discord_guild_management_moderation.dart';

/// The guild-administration routes, over the desktop-user session's REST
/// credentials.
///
/// Deliberately a separate object from the chat repository rather than more
/// methods on it. Administering a guild and reading one are different
/// authorities — most accounts hold the second and not the first — and the
/// settings window is the only caller, so folding these in would put twenty
/// methods nothing else can use in front of every consumer.
///
/// Nothing here checks a permission. That judgement needs the workspace and
/// belongs to `WorkspacePermissions`; two places deciding would eventually
/// disagree, and the one that disagreed in the moderator's favour would be the
/// bug.
final class DiscordGuildManagementRepository
    with _DiscordGuildChannelAdministration, _DiscordGuildModeration
    implements GuildManagementRepository {
  DiscordGuildManagementRepository(this._rest, {DiscordMapper? mapper})
    : _mapper = mapper ?? DiscordMapper();

  @override
  final DiscordRestClient _rest;

  @override
  final DiscordMapper _mapper;

  @override
  Future<GuildOverviewSettings> loadGuildOverview(String guildId) async =>
      DiscordGuildAdminMapper.guildOverview(
        await _rest.getObject('/guilds/${_segment(guildId)}'),
      );

  @override
  Future<GuildOverviewSettings> saveGuildOverview({
    required String guildId,
    required GuildOverviewPatch patch,
  }) async => DiscordGuildAdminMapper.guildOverview(
    await _rest.requestObject(
      'PATCH',
      '/guilds/${_segment(guildId)}',
      body: patch.toJson(),
    ),
  );

  @override
  Future<List<GuildRole>> loadRoles(String guildId) async =>
      DiscordGuildAdminMapper.roles(
        await _rest.getList('/guilds/${_segment(guildId)}/roles'),
        guildId,
      );

  @override
  Future<GuildRole> createRole({
    required String guildId,
    required GuildRoleDraft draft,
  }) async => DiscordGuildAdminMapper.role(
    await _rest.requestObject(
      'POST',
      '/guilds/${_segment(guildId)}/roles',
      body: draft.toJson(),
    ),
    guildId,
  );

  @override
  Future<GuildRole> updateRole({
    required String guildId,
    required String roleId,
    required GuildRoleEdit edit,
  }) async => DiscordGuildAdminMapper.role(
    await _rest.requestObject(
      'PATCH',
      '/guilds/${_segment(guildId)}/roles/${_segment(roleId)}',
      body: edit.toJson(),
    ),
    guildId,
  );

  @override
  Future<void> deleteRole({required String guildId, required String roleId}) =>
      _rest.requestEmpty(
        'DELETE',
        '/guilds/${_segment(guildId)}/roles/${_segment(roleId)}',
      );

  /// The whole reorder in one request, as a bare JSON array.
  ///
  /// An empty delta list is not sent at all. Discord's roles page skips the
  /// call when nothing moved, and a `PATCH` with `[]` still spends the route's
  /// tight rate-limit budget that the per-role saves are about to need.
  @override
  Future<void> reorderRoles({
    required String guildId,
    required List<RolePositionDelta> deltas,
  }) async {
    if (deltas.isEmpty) return;
    await _rest.requestJsonArray(
      'PATCH',
      '/guilds/${_segment(guildId)}/roles',
      body: [for (final delta in deltas) delta.toJson()],
    );
  }
}

/// Percent-encodes one path segment, as the renderer's endpoint-table wrapper
/// does. Snowflakes never need it; invite codes do.
String _segment(String value) => Uri.encodeComponent(value);
