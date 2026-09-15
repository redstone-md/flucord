import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/app_authorisation.dart';
import '../domain/chat_models.dart';
import '../domain/discord_permissions.dart';
import '../domain/workspace_permissions.dart';

/// One guild the app could be added to.
///
/// Only guilds the account can add an app to are offered: MANAGE_GUILD is
/// what Discord itself checks on the web page, and offering a server the
/// consent would only fail for is worse than leaving it out.
final class AuthorisableGuild {
  const AuthorisableGuild({required this.id, required this.name, this.iconUrl});

  final String id;
  final String name;
  final String? iconUrl;
}

enum AppAuthorisationStage {
  idle,
  readingInvite,
  awaitingConsent,
  adding,
  added,
}

/// Drives the bot and app authorisation page.
///
/// The conversation the desktop client puts on its own authorisation window:
/// read the invite, say who it adds and what it asks for, let the person pick
/// a server, and consent. Nothing is added until the person says to.
final class AppAuthorisationController extends ChangeNotifier {
  AppAuthorisationController(this._repositoryProvider, this._workspaceReader);

  final AppAuthorisationRepository? Function() _repositoryProvider;
  final ChatWorkspace? Function() _workspaceReader;

  AppAuthorisationStage _stage = AppAuthorisationStage.idle;
  AppInvite? _invite;
  AppInviteApplication? _application;
  List<AuthorisableGuild> _guilds = const [];
  String? _selectedGuildId;
  Object? _error;
  AppAuthorisationException? _refusal;
  bool _disposed = false;

  List<AuthorisedApplication> _grants = const [];
  bool _grantsLoaded = false;
  bool _grantsLoading = false;
  bool _revoking = false;
  String? _revokeRefusal;

  /// The apps this account has already let in.
  List<AuthorisedApplication> get grants => List.unmodifiable(_grants);

  bool get areGrantsLoading => _grantsLoading;

  /// The app Discord refused to revoke, named so the page can say which one
  /// rather than read the refusal as an outage.
  String? get revokeRefusal => _revokeRefusal;

  bool get isRevoking => _revoking;

  AppAuthorisationStage get stage => _stage;
  AppInvite? get invite => _invite;
  AppInviteApplication? get application => _application;
  List<AuthorisableGuild> get guilds => List.unmodifiable(_guilds);
  String? get selectedGuildId => _selectedGuildId;
  Object? get error => _error;
  bool get isAvailable => _repositoryProvider() != null;

  /// The refusal Discord answered the consent with, if any. Named so the
  /// page says which one it was rather than reading it as an outage.
  AppAuthorisationException? get refusal => _refusal;

  /// The permissions the invite asks for, as plain labels.
  ///
  /// Built from the same permission table the role editor uses, so a bot's
  /// request reads the way a role's grant does.
  List<String> get requestedPermissionLabels {
    final invite = _invite;
    if (invite == null) return const [];
    final named = _permissionNames.entries
        .where(
          (entry) => DiscordPermissions.hasAll(invite.permissions, entry.value),
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    return named.isEmpty && invite.addsBot
        ? const ['No extra permissions']
        : named;
  }

  /// Reads an invite link and states what it asks for.
  ///
  /// A link that is not an app invite clears the page: the answer to "what
  /// does this ask for" is "nothing, this is not an app invite", and leaving
  /// the previous app on screen under a new link would be showing the wrong
  /// consent screen.
  Future<bool> readInvite(String link) async {
    final repository = _repositoryProvider();
    if (repository == null) return false;
    final uri = Uri.tryParse(link.trim());
    final invite = uri == null ? null : repository.parseInvite(uri);
    if (invite == null) {
      _invite = null;
      _application = null;
      _stage = AppAuthorisationStage.idle;
      _refusal = null;
      _error = null;
      _notify();
      return false;
    }
    _stage = AppAuthorisationStage.readingInvite;
    _invite = invite;
    _application = null;
    _refusal = null;
    _error = null;
    _selectedGuildId = invite.guildId;
    _notify();
    try {
      _application = await repository.loadApplication(invite.applicationId);
      _guilds = _readGuilds();
      if (_selectedGuildId == null && _guilds.isNotEmpty) {
        _selectedGuildId = _guilds.first.id;
      }
      _stage = AppAuthorisationStage.awaitingConsent;
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _notify();
    }
  }

  /// Picks the guild to add the app to.
  void selectGuild(String guildId) {
    if (_selectedGuildId == guildId) return;
    _selectedGuildId = guildId;
    _notify();
  }

  /// Consents and adds the app to the chosen guild.
  Future<bool> consent() async {
    final repository = _repositoryProvider();
    final invite = _invite;
    final guildId = _selectedGuildId;
    if (repository == null || invite == null || guildId == null) return false;
    if (_stage == AppAuthorisationStage.adding ||
        _stage == AppAuthorisationStage.added) {
      return false;
    }
    _stage = AppAuthorisationStage.adding;
    _refusal = null;
    _error = null;
    _notify();
    try {
      await repository.consent(invite: invite, guildId: guildId);
      _stage = AppAuthorisationStage.added;
      return true;
    } on AppAuthorisationException catch (error) {
      _refusal = error;
      _stage = AppAuthorisationStage.awaitingConsent;
      return false;
    } on Object catch (error) {
      _error = error;
      _stage = AppAuthorisationStage.awaitingConsent;
      return false;
    } finally {
      _notify();
    }
  }

  /// Drops the invite and returns the page to its empty state.
  void reset() {
    _stage = AppAuthorisationStage.idle;
    _invite = null;
    _application = null;
    _guilds = const [];
    _selectedGuildId = null;
    _refusal = null;
    _error = null;
    _notify();
  }

  /// Loads the grants this account has made, once when the page opens and
  /// again only when asked.
  Future<void> loadAuthorisedApplications({bool refresh = false}) async {
    if (_grantsLoading) return;
    if (_grantsLoaded && !refresh) return;
    final repository = _repositoryProvider();
    if (repository == null) return;
    _grantsLoading = true;
    _revokeRefusal = null;
    _error = null;
    _notify();
    try {
      _grants = await repository.loadAuthorisedApplications();
      _grantsLoaded = true;
    } on Object catch (error) {
      _error = error;
    } finally {
      _grantsLoading = false;
      _notify();
    }
  }

  /// Takes a grant back.
  ///
  /// Returns false when Discord refused, and names the app so the page can
  /// say which one rather than read the refusal as an outage.
  Future<bool> revokeAuthorisedApplication(
    AuthorisedApplication application,
  ) async {
    final repository = _repositoryProvider();
    if (repository == null || _revoking) return false;
    _revoking = true;
    _revokeRefusal = null;
    _notify();
    try {
      await repository.revokeAuthorisedApplication(application);
      _grants = [
        for (final other in _grants)
          if (other != application) other,
      ];
      return true;
    } on AppAuthorisationException {
      _revokeRefusal = application.name;
      return false;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _revoking = false;
      _notify();
    }
  }

  /// The guilds this account may add an app to, in the workspace's own order.
  ///
  /// Read live rather than cached: the workspace is replaced when the
  /// account reconnects, and a consent built against a stale one would name
  /// a server the session may no longer reach.
  List<AuthorisableGuild> _readGuilds() {
    final workspace = _workspaceReader();
    if (workspace == null) return const [];
    final permissions = WorkspacePermissions(workspace);
    return [
      for (final space in workspace.spaces)
        if (!space.isDirectMessages &&
            permissions.canInSpace(DiscordPermissions.manageGuild, space.id))
          AuthorisableGuild(
            id: space.id,
            name: space.name,
            iconUrl: space.iconUrl,
          ),
    ];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The permissions a bot invite most often names, with the labels the role
  /// editor uses. A bit this table does not name still travels on the
  /// consent request; it is only the label list that keeps to the ones a
  /// person can read at a glance.
  ///
  /// Final rather than const because the permission masks are BigInts, which
  /// cannot appear in a const map.
  static final Map<String, BigInt> _permissionNames = {
    'Administrator': DiscordPermissions.administrator,
    'Manage server': DiscordPermissions.manageGuild,
    'Manage channels': DiscordPermissions.manageChannels,
    'Manage roles': DiscordPermissions.manageRoles,
    'Kick members': DiscordPermissions.kickMembers,
    'Ban members': DiscordPermissions.banMembers,
    'Time out members': DiscordPermissions.moderateMembers,
    'Manage messages': DiscordPermissions.manageMessages,
    'Mention everyone': DiscordPermissions.mentionEveryone,
    'View audit log': DiscordPermissions.viewAuditLog,
    'Send messages': DiscordPermissions.sendMessages,
    'Embed links': DiscordPermissions.embedLinks,
    'Attach files': DiscordPermissions.attachFiles,
    'Read message history': DiscordPermissions.readMessageHistory,
    'Add reactions': DiscordPermissions.addReactions,
    'View channels': DiscordPermissions.viewChannel,
    'Connect to voice': DiscordPermissions.connect,
    'Speak in voice': DiscordPermissions.speak,
    'Mute members': DiscordPermissions.muteMembers,
    'Deafen members': DiscordPermissions.deafenMembers,
    'Move members': DiscordPermissions.moveMembers,
    'Manage nicknames': DiscordPermissions.manageNicknames,
    'Manage webhooks': DiscordPermissions.manageWebhooks,
    'Manage expressions': DiscordPermissions.manageGuildExpressions,
    'Manage events': DiscordPermissions.manageEvents,
    'Manage threads': DiscordPermissions.manageThreads,
    'Use external emoji': DiscordPermissions.useExternalEmojis,
    'Use external stickers': DiscordPermissions.useExternalStickers,
  };
}
