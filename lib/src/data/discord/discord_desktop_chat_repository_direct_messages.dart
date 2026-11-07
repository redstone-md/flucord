part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryDirectMessages
    implements DirectMessageManagementRepository {
  DiscordDesktopApiClient get _api;
  DiscordDirectMessages get _directMessages;
  String? get _currentMemberId;

  Future<DirectConversation> openDirectConversation(String recipientId) async {
    final currentUserId = _currentMemberId;
    if (currentUserId == null) throw StateError('Workspace is not loaded');
    return _directMessages.open(recipientId, currentUserId);
  }

  @override
  Future<DirectConversation> createGroupDirectMessage(
    List<String> recipientIds,
  ) async {
    final currentUserId = _currentMemberId;
    if (currentUserId == null) throw StateError('Workspace is not loaded');
    final payload = await _api.createGroupDirectMessageChannel(recipientIds);
    return _directMessages.adoptOpened(payload, currentUserId);
  }

  /// The list changes with the `CHANNEL_RECIPIENT_ADD` that follows.
  @override
  Future<void> addGroupRecipient({
    required String channelId,
    required String userId,
  }) => _api.putChannelRecipient(channelId, userId);

  /// The list changes with the `CHANNEL_RECIPIENT_REMOVE` that follows.
  @override
  Future<void> removeGroupRecipient({
    required String channelId,
    required String userId,
  }) => _api.deleteChannelRecipient(channelId, userId);

  @override
  Future<void> renameGroupDirectMessage(String channelId, String name) =>
      _editGroupDirectMessage(channelId, {'name': name});

  @override
  Future<void> setGroupDirectMessageIcon(
    String channelId,
    String? iconDataUri,
  ) => _editGroupDirectMessage(channelId, {'icon': iconDataUri});

  /// Applies Discord's answer at once rather than waiting for the
  /// `CHANNEL_UPDATE` that repeats it.
  Future<void> _editGroupDirectMessage(
    String channelId,
    Map<String, Object?> body,
  ) async {
    final payload = await _api.patchGroupDirectMessage(channelId, body);
    final currentUserId = _currentMemberId;
    if (currentUserId != null) {
      await _directMessages.acceptChannel(payload, currentUserId);
    }
  }

  @override
  Future<void> closeDirectMessage(String channelId) async {
    await _api.closePrivateChannel(channelId);
    await _directMessages.close(channelId);
  }
}
