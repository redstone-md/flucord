part of 'chat_controller.dart';

/// Starting and running group DMs, and closing DMs. Each action answers
/// whether Discord took it.
extension ChatControllerDirectMessages on ChatController {
  DirectMessageManagementRepository? get _directMessageManagement =>
      _repository is DirectMessageManagementRepository
      ? _repository as DirectMessageManagementRepository
      : null;

  /// Whether this session can start, run and close DMs.
  bool get canManageDirectMessages => _directMessageManagement != null;

  /// Starts a group DM with [recipientIds] and answers its channel id, or
  /// null when Discord refused.
  Future<String?> createGroupDirectMessage(List<String> recipientIds) async {
    final repository = _directMessageManagement;
    if (repository == null || _workspace == null || recipientIds.length < 2) {
      return null;
    }
    DirectConversation? created;
    await _directMessageAction('start a group DM', () async {
      created = await repository.createGroupDirectMessage(recipientIds);
    });
    final conversation = created;
    if (conversation == null ||
        !_adoptConversation(conversation, from: repository)) {
      return null;
    }
    return conversation.channel.id;
  }

  Future<bool> addGroupRecipient(String channelId, String userId) => _onGroup(
    channelId,
    'add somebody to a group DM',
    (repository) =>
        repository.addGroupRecipient(channelId: channelId, userId: userId),
  );

  /// Only the group's owner may remove somebody, so nobody else asks.
  Future<bool> removeGroupRecipient(String channelId, String userId) async {
    final workspace = _workspace;
    if (workspace?.channelOrNull(channelId)?.ownerId !=
        workspace?.currentMemberId) {
      return false;
    }
    return _onGroup(
      channelId,
      'remove somebody from a group DM',
      (repository) =>
          repository.removeGroupRecipient(channelId: channelId, userId: userId),
    );
  }

  Future<bool> renameGroupDirectMessage(String channelId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    return _onGroup(
      channelId,
      'rename a group DM',
      (repository) => repository.renameGroupDirectMessage(channelId, trimmed),
    );
  }

  /// Sets the group's picture to [iconDataUri], or removes it with null.
  Future<bool> setGroupDirectMessageIcon(
    String channelId,
    String? iconDataUri,
  ) => _onGroup(
    channelId,
    'change a group DM icon',
    (repository) =>
        repository.setGroupDirectMessageIcon(channelId, iconDataUri),
  );

  /// Leaves a group DM or closes a DM with one person, and takes it off the
  /// list.
  Future<bool> closeDirectMessage(String channelId) async {
    final repository = _directMessageManagement;
    if (repository == null ||
        _workspace?.channelOrNull(channelId)?.isDirectMessage != true) {
      return false;
    }
    final closed = await _directMessageAction(
      'close a DM',
      () => repository.closeDirectMessage(channelId),
    );
    if (!closed) return false;
    _removeChannel(channelId);
    _notify();
    return true;
  }

  Future<bool> _onGroup(
    String channelId,
    String what,
    Future<void> Function(DirectMessageManagementRepository repository) action,
  ) async {
    final repository = _directMessageManagement;
    if (repository == null ||
        _workspace?.channelOrNull(channelId)?.isGroupDirectMessage != true) {
      return false;
    }
    return _directMessageAction(what, () => action(repository));
  }

  Future<bool> _directMessageAction(
    String what,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return true;
    } catch (error) {
      AppLog.warning('chat.dm', 'Could not $what', error: error);
      return false;
    }
  }
}
