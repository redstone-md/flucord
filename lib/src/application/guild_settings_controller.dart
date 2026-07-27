import 'package:flutter/foundation.dart';

import '../domain/chat_models.dart';
import '../domain/guild_audit_log.dart';
import '../domain/guild_management.dart';
import '../domain/guild_management_repository.dart';
import '../domain/workspace_permissions.dart';

part 'guild_settings_controller_channels.dart';
part 'guild_settings_controller_moderation.dart';
part 'guild_settings_controller_roles.dart';

/// The pages of the server-settings window.
enum GuildSettingsSection { overview, roles, channels, bans, invites, auditLog }

/// Drives the server-settings window.
///
/// Each section loads on first open and never again unless asked. Discord's own
/// window does the same, and the reason is not politeness: the audit log and
/// the ban list are the two most rate-limited routes on the guild, and a
/// controller that refreshed everything on every rebuild would spend a
/// moderator's budget before they clicked anything.
///
/// Every mutation is checked against [capabilities] before it is sent. The UI
/// already hides what the account may not do, so a refusal here means the two
/// disagreed — and the safe way to disagree about a destructive action is to
/// not perform it.
final class GuildSettingsController extends ChangeNotifier {
  GuildSettingsController(
    this._repository,
    this._capabilities, {
    required this.guildId,
  });

  final GuildManagementRepository _repository;
  final String guildId;

  GuildAdminCapabilities _capabilities;

  final Set<GuildSettingsSection> _loading = {};
  final Set<GuildSettingsSection> _loaded = {};
  final Map<GuildSettingsSection, Object> _errors = {};

  GuildSettingsSection _section = GuildSettingsSection.overview;
  GuildOverviewSettings? _overview;
  List<GuildRole> _roles = const [];
  List<GuildBan> _bans = const [];
  List<GuildInvite> _invites = const [];
  List<AuditLogRecord> _auditRecords = const [];
  Map<String, String> _auditUserNames = const {};
  AuditLogQuery _auditQuery = const AuditLogQuery();
  bool _hasOlderAuditEntries = false;
  bool _busy = false;
  Object? _actionError;
  bool _disposed = false;

  GuildAdminCapabilities get capabilities => _capabilities;

  /// Re-reads the permission answer after the workspace changed.
  ///
  /// A role edit can remove the very permission the open window is built on,
  /// and the gateway tells us so within a frame or two. Keeping the stale copy
  /// would leave a delete button on screen that the server now refuses.
  set capabilities(GuildAdminCapabilities value) {
    _capabilities = value;
    _notify();
  }

  GuildSettingsSection get section => _section;
  GuildOverviewSettings? get overview => _overview;
  List<GuildRole> get roles => List.unmodifiable(_roles);
  List<GuildBan> get bans => List.unmodifiable(_bans);
  List<GuildInvite> get invites => List.unmodifiable(_invites);
  List<AuditLogRecord> get auditRecords => List.unmodifiable(_auditRecords);
  Map<String, String> get auditUserNames => Map.unmodifiable(_auditUserNames);
  AuditLogQuery get auditQuery => _auditQuery;
  bool get hasOlderAuditEntries => _hasOlderAuditEntries;

  /// A write is in flight. One flag for the whole window: the sections share a
  /// guild and letting two writes race on it is how a reorder lands on top of a
  /// delete.
  bool get isBusy => _busy;

  /// Why the last write failed, or `null`.
  Object? get actionError => _actionError;

  bool isLoading(GuildSettingsSection section) => _loading.contains(section);

  Object? errorFor(GuildSettingsSection section) => _errors[section];

  /// The sections this account may open, in window order.
  List<GuildSettingsSection> get availableSections => [
    for (final section in GuildSettingsSection.values)
      if (_isPermitted(section)) section,
  ];

  bool _isPermitted(GuildSettingsSection section) => switch (section) {
    GuildSettingsSection.overview => _capabilities.canManageGuild,
    GuildSettingsSection.roles => _capabilities.canManageRoles,
    GuildSettingsSection.channels => _capabilities.canManageChannels,
    GuildSettingsSection.bans => _capabilities.canBanMembers,
    GuildSettingsSection.invites => _capabilities.canManageGuild,
    GuildSettingsSection.auditLog => _capabilities.canViewAuditLog,
  };

  /// Opens [section], loading it the first time.
  Future<void> openSection(GuildSettingsSection section) async {
    if (!_isPermitted(section)) return;
    _section = section;
    _actionError = null;
    _notify();
    await load(section);
  }

  /// Loads [section]'s data. Already-loaded sections are left alone unless
  /// [refresh] is set.
  Future<void> load(
    GuildSettingsSection section, {
    bool refresh = false,
  }) async {
    if (!_isPermitted(section)) return;
    if (_loading.contains(section)) return;
    if (_loaded.contains(section) && !refresh) return;
    _loading.add(section);
    _errors.remove(section);
    _notify();
    try {
      await _fetch(section);
      _loaded.add(section);
    } on Object catch (error) {
      _errors[section] = error;
    } finally {
      _loading.remove(section);
      _notify();
    }
  }

  Future<void> _fetch(GuildSettingsSection section) async {
    switch (section) {
      case GuildSettingsSection.overview:
        _overview = await _repository.loadGuildOverview(guildId);
      case GuildSettingsSection.roles:
        _roles = (await _repository.loadRoles(guildId))
          ..sort(GuildRole.compareForDisplay);
      case GuildSettingsSection.channels:
        // Channels come from the workspace the shell already holds; this
        // section only writes.
        break;
      case GuildSettingsSection.bans:
        _bans = await _repository.loadBans(guildId: guildId);
      case GuildSettingsSection.invites:
        _invites = await _repository.loadGuildInvites(guildId);
      case GuildSettingsSection.auditLog:
        await _fetchAuditPage(_auditQuery, append: false);
    }
  }

  /// Saves a partial guild patch.
  Future<bool> saveOverview(GuildOverviewPatch patch) async {
    if (!_capabilities.canManageGuild || patch.isEmpty) return false;
    return _run(() async {
      _overview = await _repository.saveGuildOverview(
        guildId: guildId,
        patch: patch,
      );
    });
  }

  /// Runs one write, serialised against every other write in this window.
  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      await action();
      return true;
    } on Object catch (error) {
      _actionError = error;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
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
