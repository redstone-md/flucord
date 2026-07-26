import 'discord_permissions.dart';
import 'guild_membership.dart';
import 'permission_overwrite.dart';

/// Who a permission question is being asked about.
final class PermissionSubject {
  const PermissionSubject({
    required this.userId,
    this.membership,
    this.isCurrentUser = false,
    this.hasMultiFactorAuth = true,
    this.isLurking = false,
  });

  final String userId;

  /// Null when the guild never told us about this member. The overwrite pass
  /// then applies the `@everyone` overwrite only, exactly as Discord does for
  /// a member it has no record of.
  final GuildMembership? membership;

  /// Only the signed-in account is subject to the two-factor strip.
  final bool isCurrentUser;

  /// Defaults to true because "we do not know" must not silently strip a
  /// moderator's own buttons: the strip is a restriction, and applying it on a
  /// guess would hide actions the account really has.
  final bool hasMultiFactorAuth;

  /// Previewing a guild without having joined it.
  final bool isLurking;
}

/// The thread facts the parent-derived permissions have to be adjusted by.
final class ThreadContext {
  const ThreadContext({
    this.isPrivate = false,
    this.isMedia = false,
    this.isLocked = false,
    this.hasJoined = false,
  });

  final bool isPrivate;
  final bool isMedia;
  final bool isLocked;

  /// Whether the subject is a member of the thread.
  final bool hasJoined;
}

/// Computes effective permissions inside one guild.
///
/// This is the whole of Discord's algorithm and nothing else: it holds no
/// caches, reads no clocks it was not given, and knows nothing about channels
/// beyond their overwrite map. Everything that decides *which* inputs to feed
/// it — which roles a workspace happens to know, what a missing record means —
/// belongs to the caller, so that this part stays exhaustively checkable.
///
/// Order is load-bearing and matches the renderer exactly:
/// owner shortcut, then `@everyone` role ∪ member roles, then the
/// `ADMINISTRATOR` short-circuit, then channel overwrites
/// (`@everyone` → union of role overwrites → member), then the timeout and
/// quarantine clamps, then lurker/pending, then guest, and finally the
/// two-factor strip. Reordering any pair of these changes results.
final class GuildPermissions {
  const GuildPermissions({
    required this.guildId,
    required this.rolePermissions,
    this.ownerId,
    this.requiresMultiFactorAuth = false,
  });

  final String guildId;

  /// Role id to permission bits. The `@everyone` role is keyed by [guildId].
  final Map<String, BigInt> rolePermissions;

  final String? ownerId;

  /// The guild's `mfa_level` is elevated.
  final bool requiresMultiFactorAuth;

  /// Guild-wide permissions, with no channel in the picture.
  BigInt of(PermissionSubject subject, {DateTime? now}) =>
      inChannel(subject, now: now);

  /// Permissions inside a channel carrying [overwrites].
  ///
  /// Pass an empty map for a channel with no overwrites; the result is then the
  /// guild-wide value, which is also why [of] simply delegates here. The
  /// timeout and quarantine clamps live inside the overwrite pass and therefore
  /// apply to both.
  BigInt inChannel(
    PermissionSubject subject, {
    Map<String, DiscordPermissionOverwrite> overwrites = const {},
    DateTime? now,
  }) {
    // The owner shortcut runs before everything and skips every clamp except
    // the two-factor strip.
    if (ownerId != null && subject.userId == ownerId) {
      return _stripMultiFactor(DiscordPermissions.all, subject);
    }
    var permissions =
        rolePermissions[guildId] ?? DiscordPermissions.defaultEveryone;
    for (final roleId in subject.membership?.roleIds ?? const <String>[]) {
      final role = rolePermissions[roleId];
      // A role id we hold no record for is skipped rather than treated as
      // empty: it grants nothing either way, and refusing the whole
      // computation over one stale id would blank a live member.
      if (role != null) permissions |= role;
    }
    // ADMINISTRATOR is judged on the role-derived base alone. An overwrite that
    // grants it does not skip the overwrite pass, though it does exempt the
    // member from the clamps inside it.
    permissions =
        DiscordPermissions.hasAll(permissions, DiscordPermissions.administrator)
        ? DiscordPermissions.all
        : _applyOverwrites(
            permissions,
            subject,
            overwrites,
            now ?? DateTime.now(),
          );
    if (subject.isLurking || (subject.membership?.isPending ?? false)) {
      permissions &= DiscordPermissions.lurker;
    }
    if (subject.membership?.isGuest ?? false) {
      permissions &= DiscordPermissions.guest;
    }
    return _stripMultiFactor(permissions, subject);
  }

  /// Adjusts a thread's parent permissions for the thread itself.
  ///
  /// A thread's own `permission_overwrites` are never read — Discord derives
  /// everything from the parent — so this takes the already-computed parent
  /// value rather than a channel.
  static BigInt inThread(
    BigInt parentPermissions, {
    required ThreadContext thread,
    bool isGuest = false,
  }) {
    if (thread.isMedia) {
      return DiscordPermissions.combine([
        DiscordPermissions.readMessageHistory,
        DiscordPermissions.viewChannel,
      ]);
    }
    final canManage = DiscordPermissions.hasAll(
      parentPermissions,
      DiscordPermissions.manageThreads,
    );
    if (thread.isPrivate && !thread.hasJoined && !isGuest && !canManage) {
      return DiscordPermissions.none;
    }
    // SEND_MESSAGES inside a thread is derived, never inherited: the parent's
    // own bit is overwritten either way.
    if (!DiscordPermissions.hasAll(
      parentPermissions,
      DiscordPermissions.sendMessagesInThreads,
    )) {
      return DiscordPermissions.remove(
        parentPermissions,
        DiscordPermissions.sendMessages,
      );
    }
    return thread.isLocked && !canManage
        ? DiscordPermissions.remove(
            parentPermissions,
            DiscordPermissions.sendMessages,
          )
        : DiscordPermissions.add(
            parentPermissions,
            DiscordPermissions.sendMessages,
          );
  }

  BigInt _applyOverwrites(
    BigInt permissions,
    PermissionSubject subject,
    Map<String, DiscordPermissionOverwrite> overwrites,
    DateTime now,
  ) {
    var result = permissions;
    // The `@everyone` overwrite is keyed by the guild id and applies even to a
    // member we hold no record for.
    final everyone = overwrites[guildId];
    if (everyone != null) result = _apply(result, everyone);
    final membership = subject.membership;
    if (membership == null) return result;
    // Denies from *all* role overwrites are unioned and applied before allows
    // from *all* role overwrites. Applying each role in turn would let one
    // role's deny beat another role's allow, which Discord does not do.
    var allow = DiscordPermissions.none;
    var deny = DiscordPermissions.none;
    for (final roleId in membership.roleIds) {
      final overwrite = overwrites[roleId];
      if (overwrite == null) continue;
      allow |= overwrite.allow;
      deny |= overwrite.deny;
    }
    result = DiscordPermissions.add(
      DiscordPermissions.remove(result, deny),
      allow,
    );
    final member = overwrites[subject.userId];
    if (member != null) result = _apply(result, member);
    final isAdministrator = DiscordPermissions.hasAll(
      result,
      DiscordPermissions.administrator,
    );
    if (!isAdministrator && membership.isQuarantined) {
      result &= DiscordPermissions.quarantine;
    }
    if (!isAdministrator && membership.isTimedOutAt(now)) {
      result &= DiscordPermissions.timeout;
    }
    return result;
  }

  static BigInt _apply(BigInt permissions, DiscordPermissionOverwrite value) =>
      DiscordPermissions.add(
        DiscordPermissions.remove(permissions, value.deny),
        value.allow,
      );

  BigInt _stripMultiFactor(BigInt permissions, PermissionSubject subject) =>
      requiresMultiFactorAuth &&
          subject.isCurrentUser &&
          !subject.hasMultiFactorAuth
      ? DiscordPermissions.remove(permissions, DiscordPermissions.mfaGated)
      : permissions;
}
