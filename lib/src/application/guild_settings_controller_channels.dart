part of 'guild_settings_controller.dart';

extension GuildSettingsControllerChannels on GuildSettingsController {
  Future<bool> createChannel(GuildChannelDraft draft) async {
    if (!_capabilities.canManageChannels) return false;
    return _run(
      () => _repository.createGuildChannel(guildId: guildId, draft: draft),
    );
  }

  Future<bool> saveChannel({
    required String channelId,
    required GuildChannelEdit edit,
  }) async {
    if (!_capabilities.canManageChannels || edit.isEmpty) return false;
    return _run(
      () => _repository.editGuildChannel(channelId: channelId, edit: edit),
    );
  }

  Future<bool> deleteChannel(String channelId) async {
    if (!_capabilities.canManageChannels) return false;
    return _run(() => _repository.deleteGuildChannel(channelId));
  }

  /// Sends a reordered channel list as one sparse batch.
  ///
  /// The caller supplies both orderings rather than a "move this one there"
  /// instruction: the delta pass needs to know what every channel's position
  /// was to decide which of them actually moved, and sending the ones that did
  /// not is what makes a sidebar shuffle itself after a drag.
  Future<bool> reorderChannels({
    required List<ChannelOrderEntry> before,
    required List<ChannelOrderEntry> after,
    String? movedChannelId,
    String? newParentId,
    bool lockPermissions = false,
  }) async {
    if (!_capabilities.canManageChannels) return false;
    final deltas = channelReorderDeltas(
      before: before,
      after: after,
      movedChannelId: movedChannelId,
      newParentId: newParentId,
      lockPermissions: lockPermissions,
    );
    if (deltas.isEmpty) return false;
    return _run(
      () => _repository.reorderGuildChannels(guildId: guildId, deltas: deltas),
    );
  }
}
