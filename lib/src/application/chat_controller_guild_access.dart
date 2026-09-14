part of 'chat_controller.dart';

/// Joining, creating and leaving servers.
///
/// The routes live on the guild-management contract; this is the fold that
/// makes their answers visible: a joined or created server lands in the
/// workspace whole, so the rail and the channel tree fill without a restart,
/// and a left server is gone from both and from the cache. Persistence is the
/// transport's half: the sinks it wires answer for what a restart restores.
extension ChatControllerGuildAccess on ChatController {
  GuildManagementRepository? get _guildManagement =>
      _repository.guildManagement;

  /// Resolves an invite code to the preview the join surface shows.
  ///
  /// Invalid and expired invites refuse with [GuildAccessException]; the
  /// caller shows the message rather than an error state, because the refusal
  /// is an answer about the invite, not a failure of the client.
  Future<InvitePreview> previewInvite(String code) async {
    final repository = _guildManagement;
    if (repository == null) {
      throw const GuildAccessException(
        refusal: GuildAccessRefusal.unknown,
        message: 'This session cannot join servers.',
      );
    }
    return repository.previewInvite(code);
  }

  /// Joins the server an invite names. Answers the joined space's id, or
  /// null when the join was refused.
  ///
  /// The workspace folds the whole hydration answer, so the new server is on
  /// the rail immediately with its channels, categories and roles; its own
  /// scheduled events load lazily the way every other space's do.
  Future<String?> joinGuild(String code) async {
    final repository = _guildManagement;
    if (repository == null) return null;
    final JoinedGuild guild;
    try {
      guild = await repository.joinGuild(code);
    } on GuildAccessException catch (error) {
      _guildAccessError = error.message;
      _notify();
      return null;
    }
    _workspace = _workspace?.mergeGuild(guild);
    _guildAccessError = null;
    _notify();
    return guild.space.id;
  }

  /// Creates a server named [name]. Answers the new space's id, or null on
  /// refusal.
  ///
  /// A created server must look exactly like a joined one: same fold, same
  /// persistence, same lazy loads.
  Future<String?> createGuild(String name) async {
    final repository = _guildManagement;
    if (repository == null) return null;
    final JoinedGuild guild;
    try {
      guild = await repository.createGuild(name: name);
    } on GuildAccessException catch (error) {
      _guildAccessError = error.message;
      _notify();
      return null;
    }
    _workspace = _workspace?.mergeGuild(guild);
    _guildAccessError = null;
    _notify();
    return guild.space.id;
  }

  /// Leaves the server [spaceId]. Answers whether it is gone.
  ///
  /// A refused leave (an owner leaving their own server) surfaces as the
  /// transport's message in [guildAccessError] rather than as a silent no.
  Future<bool> leaveGuild(String spaceId) async {
    final repository = _guildManagement;
    final workspace = _workspace;
    if (repository == null || workspace == null) return false;
    try {
      await repository.leaveGuild(spaceId);
    } on GuildAccessException catch (error) {
      _guildAccessError = error.message;
      _notify();
      return false;
    }
    _workspace = workspace.removeGuild(spaceId);
    _guildAccessError = null;
    _notify();
    return true;
  }

  /// Why the last join, create or leave was refused, or null.
  String? get guildAccessError => _guildAccessError;

  /// Clears the last refusal message, once the surface that showed it has
  /// been seen.
  void clearGuildAccessError() {
    if (_guildAccessError == null) return;
    _guildAccessError = null;
    _notify();
  }
}
