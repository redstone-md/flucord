import 'package:flutter/foundation.dart';

import '../domain/chat_models.dart';
import '../domain/guild_management.dart';
import '../domain/guild_management_repository.dart';
import '../domain/workspace_permissions.dart';

/// Drives the moderation block on one member's popover.
///
/// Built per popover and disposed with it, the same lifecycle the settings
/// window's controller keeps: a member's roles and timeout are a page of
/// guild state, and a popover that outlived its member would pin that page
/// for the session.
///
/// Every action is checked against [capabilities] before it is sent. The
/// popover hides what the account may not do, so a refusal here means the two
/// disagreed, and the safe way to disagree about a destructive action is to
/// not perform it.
final class GuildMemberAdminController extends ChangeNotifier {
  GuildMemberAdminController(
    this._repository,
    this.capabilities, {
    required this.guildId,
    required this.userId,
  });

  final GuildManagementRepository _repository;
  final GuildAdminCapabilities capabilities;
  final String guildId;
  final String userId;

  GuildMemberProfile? _profile;
  List<GuildRole> _roles = const [];
  Object? _error;
  bool _busy = false;
  bool _disposed = false;

  /// The member as the server last described them, or `null` until asked.
  GuildMemberProfile? get profile => _profile;

  /// The guild's roles, the list the popover's role checkboxes are built from.
  List<GuildRole> get roles => List.unmodifiable(_roles);

  /// Why the last action failed, or `null`.
  Object? get error => _error;

  bool get isBusy => _busy;

  /// Whether the popover has anything to offer at all: an action the account
  /// may take, or a role it may hand out.
  bool get hasAnyAction =>
      capabilities.canRename(userId) ||
      capabilities.canTimeout(userId) ||
      capabilities.canKick(userId) ||
      capabilities.canBan(userId) ||
      _roles.any((role) => _assignable(role) && !role.isEveryone);

  /// Loads the member's standing and the guild's roles.
  Future<void> load() async {
    if (_busy || _disposed) return;
    try {
      final profile = await _repository.loadMember(
        guildId: guildId,
        userId: userId,
      );
      final roles = await _repository.loadRoles(guildId);
      _profile = profile;
      _roles = [...roles]..sort(GuildRole.compareForDisplay);
    } on Object catch (error) {
      _error = error;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Whether the popover may tick or untick [role] on this member.
  bool canAssignRole(GuildRole role) =>
      !_busy && _assignable(role) && !role.isEveryone && !role.managed;

  bool _assignable(GuildRole role) =>
      capabilities.canAssignRole(userId, _asCommunityRole(role));

  /// Adds one role. The other boxes are untouched: each has its own route.
  Future<bool> grantRole(GuildRole role, {String? reason}) async {
    if (!canAssignRole(role)) return false;
    final held = _profile?.roleIds ?? const [];
    if (held.contains(role.id)) return false;
    return _run(() async {
      await _repository.grantMemberRole(
        guildId: guildId,
        userId: userId,
        roleId: role.id,
        reason: reason,
      );
      _applyProfile(roleIds: [...held, role.id]);
    });
  }

  /// Takes one role away, the same one route at a time.
  Future<bool> revokeRole(GuildRole role, {String? reason}) async {
    if (!canAssignRole(role)) return false;
    final held = _profile?.roleIds ?? const [];
    if (!held.contains(role.id)) return false;
    return _run(() async {
      await _repository.revokeMemberRole(
        guildId: guildId,
        userId: userId,
        roleId: role.id,
        reason: reason,
      );
      _applyProfile(
        roleIds: [
          for (final id in held)
            if (id != role.id) id,
        ],
      );
    });
  }

  /// Sets the nickname. An empty string removes it and restores their own
  /// name, which is Discord's own encoding of the field.
  Future<bool> setNickname(String nickname, {String? reason}) async {
    if (!capabilities.canRename(userId)) return false;
    final trimmed = nickname.trim();
    return _run(() async {
      final edit = GuildMemberEdit()
        ..nickname = trimmed.isEmpty ? null : trimmed;
      _profile = await _repository.updateMember(
        guildId: guildId,
        userId: userId,
        edit: edit,
      );
    }, reason: reason);
  }

  /// Times the member out for [duration], counted from [now].
  Future<bool> timeoutMember(
    Duration duration, {
    DateTime? now,
    String? reason,
  }) async {
    if (!capabilities.canTimeout(userId) || duration <= Duration.zero) {
      return false;
    }
    final until = (now ?? DateTime.now()).add(duration);
    return _run(() async {
      final edit = GuildMemberEdit()..timeoutUntil = until;
      _profile = await _repository.updateMember(
        guildId: guildId,
        userId: userId,
        edit: edit,
      );
    }, reason: reason);
  }

  /// Lifts an active timeout. A moment in the past would also end it, but the
  /// null is what Discord's own popover sends.
  Future<bool> liftTimeout({String? reason}) async {
    if (!capabilities.canTimeout(userId)) return false;
    if (_profile?.timeoutUntil == null) return false;
    return _run(() async {
      final edit = GuildMemberEdit()..timeoutUntil = null;
      _profile = await _repository.updateMember(
        guildId: guildId,
        userId: userId,
        edit: edit,
      );
    }, reason: reason);
  }

  Future<bool> kickMember({String? reason}) async {
    if (!capabilities.canKick(userId)) return false;
    return _run(
      () async => _repository.kickMember(
        guildId: guildId,
        userId: userId,
        reason: reason,
      ),
    );
  }

  Future<bool> banMember({String? reason}) async {
    if (!capabilities.canBan(userId)) return false;
    return _run(
      () async => _repository.banMembers(
        guildId: guildId,
        request: BanRequest(userIds: [userId], reason: reason),
      ),
    );
  }

  Future<bool> _run(Future<void> Function() action, {String? reason}) async {
    if (_busy || _disposed) return false;
    _busy = true;
    _error = null;
    _notify();
    try {
      await action();
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// The role list a caller needs to answer the hierarchy question, which is
  /// asked in `CommunityRole` terms: the workspace projection is what
  /// [GuildAdminCapabilities.canAssignRole] computes against.
  CommunityRole _asCommunityRole(GuildRole role) => CommunityRole(
    id: role.id,
    spaceId: role.guildId,
    name: role.name,
    position: role.position,
    permissions: role.permissions,
  );

  void _applyProfile({required List<String> roleIds}) {
    final profile = _profile;
    if (profile == null) return;
    _profile = GuildMemberProfile(
      userId: profile.userId,
      guildId: profile.guildId,
      roleIds: roleIds,
      nickname: profile.nickname,
      timeoutUntil: profile.timeoutUntil,
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
