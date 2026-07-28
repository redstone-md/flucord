import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_audit_log.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/domain/guild_management_repository.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'fake_automod_routes.dart';

/// Fixtures shared by the guild-settings controller and widget tests.
///
/// Every snowflake here is one of the six the repository allows in fixtures.

const guildId = '111111111111111111';
const moderatorId = '123456789012345678';
const lowMemberId = '234567890123456789';
const highMemberId = '987654321098765432';
const bannedUserId = '333333333333333333';
const textChannelId = '222222222222222222';

final allModerationPermissions = DiscordPermissions.combine([
  DiscordPermissions.viewChannel,
  DiscordPermissions.manageGuild,
  DiscordPermissions.manageRoles,
  DiscordPermissions.manageChannels,
  DiscordPermissions.banMembers,
  DiscordPermissions.kickMembers,
  DiscordPermissions.createInstantInvite,
  DiscordPermissions.viewAuditLog,
]);

/// A guild with a moderator at role position 5, a member below them and an
/// admin above them, so hierarchy has something to bite on.
ChatWorkspace guildWorkspace({BigInt? moderatorPermissions}) => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: guildId,
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: textChannelId,
      spaceId: guildId,
      name: 'general',
      topic: 'Everything else',
      kind: ChannelKind.text,
    ),
    ConversationChannel(
      id: '234567890123456789',
      spaceId: guildId,
      name: 'workbench',
      topic: '',
      kind: ChannelKind.voice,
      position: 1,
    ),
  ],
  members: const [
    Member(
      id: moderatorId,
      displayName: 'Mira',
      initials: 'MI',
      role: 'moderator',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: {guildId},
      membershipsBySpace: {
        guildId: GuildMembership(roleIds: ['moderator']),
      },
    ),
    Member(
      id: lowMemberId,
      displayName: 'Ada',
      initials: 'AD',
      role: 'member',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: {guildId},
      membershipsBySpace: {
        guildId: GuildMembership(roleIds: ['member']),
      },
    ),
    Member(
      id: highMemberId,
      displayName: 'Kai',
      initials: 'KA',
      role: 'admin',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: {guildId},
      membershipsBySpace: {
        guildId: GuildMembership(roleIds: ['admin']),
      },
    ),
  ],
  messages: const [],
  currentMemberId: moderatorId,
  roles: [
    CommunityRole(
      id: guildId,
      spaceId: guildId,
      name: '@everyone',
      position: 0,
      permissions: DiscordPermissions.viewChannel,
    ),
    const CommunityRole(
      id: 'member',
      spaceId: guildId,
      name: 'member',
      position: 1,
    ),
    CommunityRole(
      id: 'moderator',
      spaceId: guildId,
      name: 'moderator',
      position: 5,
      permissions: moderatorPermissions ?? allModerationPermissions,
    ),
    const CommunityRole(
      id: 'admin',
      spaceId: guildId,
      name: 'admin',
      position: 9,
    ),
  ],
);

/// An in-memory stand-in for the guild-administration routes.
final class FakeGuildManagementRepository
    with FakeAutoModRoutes
    implements GuildManagementRepository {
  @override
  void recordAutoModCall(String call) => _record(call);

  @override
  String get automodGuildId => guildId;

  final List<String> calls = [];

  /// The next call throws, then the flag clears itself.
  bool failNext = false;

  /// Adds an integration-owned role to the list.
  bool includeManaged = false;

  /// Adds a second role below the actor so a legal reorder exists.
  bool includeLowRoles = false;

  /// Returns a full audit page, so paging has somewhere to go.
  bool fullAuditPage = false;

  /// Returns no audit entries at all.
  bool emptyAuditPage = false;

  BanRequest? bannedRequest;
  List<RolePositionDelta>? reorderedDeltas;
  AuditLogQuery? lastAuditQuery;

  String _guildName = 'The Forge';
  int _createdRoles = 0;
  final List<String> _revokedInvites = [];
  bool _unbanned = false;

  void _record(String call) {
    calls.add(call);
    if (!failNext) return;
    failNext = false;
    throw StateError('$call failed');
  }

  @override
  Future<GuildOverviewSettings> loadGuildOverview(String id) async {
    _record('loadGuildOverview');
    return GuildOverviewSettings(
      id: id,
      name: _guildName,
      description: 'A workshop',
      afkTimeoutSeconds: 300,
      systemChannelId: textChannelId,
      verificationLevel: GuildVerificationLevel.low,
      explicitContentFilter: GuildExplicitContentFilter.disabled,
      defaultMessageNotifications: GuildNotificationLevel.onlyMentions,
    );
  }

  @override
  Future<GuildOverviewSettings> saveGuildOverview({
    required String guildId,
    required GuildOverviewPatch patch,
  }) async {
    _record('saveGuildOverview');
    _guildName = patch['name'] as String? ?? _guildName;
    return loadGuildOverview(guildId);
  }

  @override
  Future<List<GuildRole>> loadRoles(String id) async {
    _record('loadRoles');
    return [
      _role('moderator', 5),
      if (includeLowRoles) _role('helper', 2),
      _role('member', 1),
      _role(guildId, 0),
      if (includeManaged) _role('bot', 4, managed: true),
    ];
  }

  @override
  Future<GuildRole> createRole({
    required String guildId,
    required GuildRoleDraft draft,
  }) async {
    _record('createRole');
    _createdRoles++;
    return _role('created-$_createdRoles', 1, name: draft.name ?? 'new role');
  }

  @override
  Future<GuildRole> updateRole({
    required String guildId,
    required String roleId,
    required GuildRoleEdit edit,
  }) async {
    _record('updateRole');
    return _role(roleId, 1, name: edit['name'] as String? ?? roleId);
  }

  @override
  Future<void> deleteRole({
    required String guildId,
    required String roleId,
  }) async => _record('deleteRole');

  @override
  Future<void> reorderRoles({
    required String guildId,
    required List<RolePositionDelta> deltas,
  }) async {
    _record('reorderRoles');
    reorderedDeltas = deltas;
  }

  @override
  Future<ConversationChannel> createGuildChannel({
    required String guildId,
    required GuildChannelDraft draft,
  }) async {
    _record('createGuildChannel');
    return ConversationChannel(
      id: '333333333333333333',
      spaceId: guildId,
      name: draft.name,
      topic: '',
      kind: ChannelKind.text,
    );
  }

  @override
  Future<ConversationChannel> editGuildChannel({
    required String channelId,
    required GuildChannelEdit edit,
  }) async {
    _record('editGuildChannel');
    return ConversationChannel(
      id: channelId,
      spaceId: guildId,
      name: edit['name'] as String? ?? 'general',
      topic: '',
      kind: ChannelKind.text,
    );
  }

  @override
  Future<void> deleteGuildChannel(String channelId) async =>
      _record('deleteGuildChannel');

  @override
  Future<void> reorderGuildChannels({
    required String guildId,
    required List<ChannelPositionDelta> deltas,
  }) async => _record('reorderGuildChannels');

  @override
  Future<List<GuildBan>> loadBans({
    required String guildId,
    int limit = 1000,
    String? after,
  }) async {
    _record('loadBans');
    return _unbanned
        ? const []
        : const [
            GuildBan(
              userId: bannedUserId,
              userName: 'raider',
              globalName: 'Raider',
              reason: 'Spam',
            ),
          ];
  }

  @override
  Future<List<GuildBan>> searchBans({
    required String guildId,
    required String query,
    int limit = 10,
  }) async {
    _record('searchBans');
    return const [
      GuildBan(userId: bannedUserId, userName: 'raider', reason: 'Spam'),
    ];
  }

  @override
  Future<BulkBanResult> banMembers({
    required String guildId,
    required BanRequest request,
  }) async {
    _record('banMembers');
    bannedRequest = request;
    return BulkBanResult(bannedUserIds: request.userIds);
  }

  @override
  Future<void> unbanMember({
    required String guildId,
    required String userId,
    String? reason,
  }) async {
    _record('unbanMember');
    _unbanned = true;
  }

  @override
  Future<void> kickMember({
    required String guildId,
    required String userId,
    String? reason,
  }) async => _record('kickMember');

  @override
  Future<List<GuildInvite>> loadGuildInvites(String guildId) async {
    _record('loadGuildInvites');
    return [
      for (final invite in const [
        GuildInvite(
          code: 'forge',
          channelName: 'general',
          uses: 2,
          maxUses: 10,
          maxAgeSeconds: 3600,
        ),
      ])
        if (!_revokedInvites.contains(invite.code)) invite,
    ];
  }

  @override
  Future<GuildInvite> createChannelInvite({
    required String channelId,
    InviteOptions options = const InviteOptions(),
  }) async {
    _record('createChannelInvite');
    return GuildInvite(
      code: 'fresh',
      channelId: channelId,
      maxAgeSeconds: options.maxAgeSeconds,
      maxUses: options.maxUses,
    );
  }

  @override
  Future<void> revokeInvite(String code) async {
    _record('revokeInvite');
    _revokedInvites.add(code);
  }

  @override
  Future<AuditLogPage> loadAuditLog({
    required String guildId,
    AuditLogQuery query = const AuditLogQuery(),
  }) async {
    _record('loadAuditLog');
    lastAuditQuery = query;
    final entries = emptyAuditPage
        ? const <AuditLogEntry>[]
        : fullAuditPage
        ? [
            for (var index = 0; index < AuditLogQuery.pageSize; index++)
              _entry('$index', minutes: index),
          ]
        : [_entry('987654321098765432'), _entry('222222222222222222')];
    return AuditLogPage(
      entries: entries,
      userNames: const {moderatorId: 'Mira'},
    );
  }

  GuildRole _role(
    String id,
    int position, {
    String? name,
    bool managed = false,
  }) => GuildRole(
    id: id,
    guildId: guildId,
    name: name ?? id,
    position: position,
    permissions: BigInt.zero,
    managed: managed,
  );

  AuditLogEntry _entry(String id, {int minutes = 0}) => AuditLogEntry(
    id: id,
    action: AuditLogActionType.channelUpdate,
    timestamp: DateTime.utc(2026, 7, 27, 12, minutes),
    targetId: textChannelId,
    userId: moderatorId,
    changes: const [AuditLogChange(key: 'name', oldValue: 'a', newValue: 'b')],
  );
}
