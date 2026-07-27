import 'channel_capabilities.dart';
import 'chat_models.dart';
import 'discord_permissions.dart';
import 'guild_membership.dart';
import 'guild_permissions.dart';

part 'guild_admin_capabilities.dart';

/// Answers permission questions about one workspace snapshot.
///
/// [GuildPermissions] is the algorithm; this is the part that decides what to
/// feed it, which is where every judgement call about missing data lives:
///
/// * A guild whose `@everyone` role we hold no permission bits for, or whose
///   member record for the account never arrived, is treated as *unknown*, not
///   as empty. Flucord reaches Discord through four independent transports and
///   only one of them carries both today, so folding "we were never told" into
///   "denied" would empty the sidebar of every account that is otherwise
///   working. Unknown resolves to full permissions — the behaviour that
///   shipped before this existed.
/// * Direct messages have no guild and no overwrites, so Discord's own client
///   special-cases them as fully permitted.
/// * The result is finally narrowed to the bits Discord's permission surface
///   actually offers for that kind of channel, which is what keeps a voice
///   channel's chat from sprouting threads and pins.
final class WorkspacePermissions {
  WorkspacePermissions(this._workspace, {String? memberId, DateTime? now})
    : _memberId = memberId ?? _workspace.currentMemberId,
      _now = now ?? DateTime.now();

  final ChatWorkspace _workspace;
  final String _memberId;

  /// Pinned once per instance so every channel in one pass is judged against
  /// the same moment — a timeout must not expire halfway down the sidebar.
  final DateTime _now;

  /// Guild resolvers built on demand. A sidebar asks about every channel of a
  /// guild in one pass, and rebuilding the role table per channel would turn
  /// one filter into quadratic work over the role list.
  final Map<String, GuildPermissions?> _guilds = {};
  final Map<String, BigInt> _channels = {};

  /// Effective permissions in [channel].
  BigInt inChannel(ConversationChannel channel) =>
      _channels[channel.id] ??= _resolve(channel);

  bool can(BigInt permission, ConversationChannel channel) =>
      DiscordPermissions.hasAll(inChannel(channel), permission);

  ChannelCapabilities capabilitiesIn(ConversationChannel channel) =>
      ChannelCapabilities.fromPermissions(inChannel(channel));

  /// Guild-wide permissions in [spaceId], or `null` when this client holds no
  /// permission data for that guild.
  ///
  /// Note the asymmetry with [inChannel], which resolves the same gap to *full*
  /// permissions so a sidebar built from a transport that never sent role bits
  /// still lists its channels. Guild-wide answers gate destructive work —
  /// deleting a role, banning a member, wiping a channel — and there the same
  /// fallback would offer every one of those buttons to an account nobody has
  /// confirmed may press them. A permission question that fails open is exactly
  /// the shape of the bug that once turned a `-1` bitfield into administrator.
  BigInt? inSpace(String spaceId) {
    final guild = _guildFor(spaceId);
    final membership = _membershipIn(spaceId);
    if (guild == null || membership == null) return null;
    return guild.of(
      PermissionSubject(
        userId: _memberId,
        membership: membership,
        isCurrentUser: _memberId == _workspace.currentMemberId,
      ),
      now: _now,
    );
  }

  /// Whether the account holds [permission] guild-wide in [spaceId]. Unknown
  /// permission data answers false, for the reason [inSpace] gives.
  bool canInSpace(BigInt permission, String spaceId) {
    final bits = inSpace(spaceId);
    return bits != null && DiscordPermissions.hasAll(bits, permission);
  }

  /// What the account may administer in [spaceId].
  GuildAdminCapabilities administrationOf(String spaceId) =>
      GuildAdminCapabilities._(this, spaceId);

  /// The channels of [spaceId] the account may see, in the order given.
  ///
  /// This is Discord's first-stage sidebar filter: a channel without
  /// `VIEW_CHANNEL` is not hidden, it is not listed at all.
  List<ConversationChannel> visibleChannelsFor(String spaceId) => [
    for (final channel in _workspace.channelsFor(spaceId))
      if (can(DiscordPermissions.viewChannel, channel)) channel,
  ];

  /// Membership per space, resolved once.
  ///
  /// `memberOrNull` is a linear scan of the workspace's member list, and
  /// `_resolve` runs per channel. Repeating the scan turned rendering a sidebar
  /// into O(channels x members) — twice per rebuild, on a list that grows with
  /// every roster page that arrives.
  final Map<String, GuildMembership?> _membershipCache = {};

  GuildMembership? _membershipIn(String spaceId) =>
      _membershipCache.putIfAbsent(
        spaceId,
        () => _workspace.memberOrNull(_memberId)?.membershipIn(spaceId),
      );

  BigInt _resolve(ConversationChannel channel) {
    final scoped = _unsupportedIn(channel);
    final guild = _guildFor(channel.spaceId);
    final membership = _membershipIn(channel.spaceId);
    // Knowing the guild's roles is not enough — without knowing which of them
    // this account holds, the computation would answer for a member with no
    // roles at all and hide every channel `@everyone` alone cannot see. A
    // member who truly holds none still has a record, with an empty role list,
    // so absence here really does mean the payload never reached us.
    if (guild == null || membership == null) {
      return DiscordPermissions.remove(DiscordPermissions.all, scoped);
    }
    final subject = PermissionSubject(
      userId: _memberId,
      membership: membership,
      isCurrentUser: _memberId == _workspace.currentMemberId,
    );
    if (!channel.isThread) {
      return DiscordPermissions.remove(
        guild.inChannel(
          subject,
          overwrites: channel.permissionOverwrites,
          now: _now,
        ),
        scoped,
      );
    }
    final parentId = channel.parentId;
    final parent = parentId == null ? null : _workspace.channelOrNull(parentId);
    // Discord resolves a parentless thread to no permissions. Here a thread
    // can outlive its parent record — a cached workspace keeps threads the
    // next sync no longer lists a parent for — and blanking a conversation the
    // account is demonstrably reading is worse than falling back to the guild.
    final parentPermissions = guild.inChannel(
      subject,
      overwrites: parent?.permissionOverwrites ?? const {},
      now: _now,
    );
    return DiscordPermissions.remove(
      GuildPermissions.inThread(
        parentPermissions,
        // Thread membership is not modelled: this client only ever holds
        // threads the gateway already decided to send it, so treating one as
        // unjoined would hide a thread the account is a member of.
        thread: ThreadContext(isLocked: channel.isLocked, hasJoined: true),
        isGuest: membership.isGuest,
      ),
      scoped,
    );
  }

  GuildPermissions? _guildFor(String spaceId) =>
      _guilds.putIfAbsent(spaceId, () => _buildGuild(spaceId));

  GuildPermissions? _buildGuild(String spaceId) {
    final space = _workspace.spaces.where((item) => item.id == spaceId);
    if (space.isEmpty || space.first.isDirectMessages) return null;
    final permissions = <String, BigInt>{};
    var hasEveryone = false;
    for (final role in _workspace.roles) {
      if (role.spaceId != spaceId) continue;
      final bits = role.permissions;
      if (bits == null) continue;
      permissions[role.id] = bits;
      hasEveryone |= role.isEveryone;
    }
    // Without the `@everyone` record there is no base to start from, and
    // Discord's own fallback would hand every member the default role's
    // permissions — a guess this client has no reason to make when the honest
    // answer is that it holds no permission data for this guild yet.
    if (!hasEveryone) return null;
    return GuildPermissions(
      guildId: spaceId,
      rolePermissions: permissions,
      ownerId: space.first.ownerId,
      requiresMultiFactorAuth: space.first.requiresMultiFactorAuth,
    );
  }

  /// Bits Discord's permission surface does not offer for this kind of
  /// channel, whatever the roles say.
  ///
  /// A role that grants `CREATE_PUBLIC_THREADS` guild-wide still grants it
  /// inside a voice channel's text chat, because no overwrite mentions it —
  /// yet Discord offers neither threads nor pins there. Narrowing the result
  /// is what lets every caller ask a permission question and stop
  /// special-casing channel kinds of its own.
  static BigInt _unsupportedIn(ConversationChannel channel) {
    if (channel.kind == ChannelKind.voice) return _voiceTextChat;
    if (channel.isDirectMessage) return _privateConversation;
    if (channel.isThread) return _threadCreation;
    return DiscordPermissions.none;
  }

  static final _threadCreation = DiscordPermissions.combine([
    DiscordPermissions.createPublicThreads,
    DiscordPermissions.createPrivateThreads,
  ]);

  static final _voiceTextChat = DiscordPermissions.combine([
    _threadCreation,
    DiscordPermissions.sendMessagesInThreads,
    DiscordPermissions.manageThreads,
    DiscordPermissions.pinMessages,
  ]);

  /// A direct message has no threads and nobody to moderate: neither party can
  /// remove the other's messages, however permitted everything else is.
  static final _privateConversation = DiscordPermissions.combine([
    _threadCreation,
    DiscordPermissions.sendMessagesInThreads,
    DiscordPermissions.manageThreads,
    DiscordPermissions.manageMessages,
  ]);
}
