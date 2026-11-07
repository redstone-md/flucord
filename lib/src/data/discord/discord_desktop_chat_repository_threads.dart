part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryThreads
    implements ThreadListRepository, ForumPostRepository {
  DiscordDesktopApiClient get _api;
  ChatCache get _cache;
  DiscordMapper get _mapper;
  StreamController<ChatRepositoryEvent> get _events;
  DiscordThreadDirectory get _threads;

  Future<ConversationChannel> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) async {
    final workspace = await _cache.readWorkspaceShell();
    final parent = workspace?.channelOrNull(channelId);
    if (parent == null) throw StateError('Parent channel is not cached');
    final payload = await _api.createThreadFromMessage(
      channelId: channelId,
      messageId: messageId,
      name: name,
      autoArchiveDurationMinutes: autoArchiveDurationMinutes,
    );
    final channel = _mapper.channel(payload, parent.spaceId);
    if (channel == null) throw StateError('Discord returned an invalid thread');
    await _cache.writeChannel(channel);
    _events.add(ChannelUpsertedEvent(channel));
    return channel;
  }

  @override
  Future<ThreadPage> loadThreads(
    String parentId, {
    int offset = 0,
    Set<String> tagIds = const {},
  }) => _threads.loadThreads(parentId, offset: offset, tagIds: tagIds);

  @override
  Future<CreatedForumPost> createForumPost({
    required String channelId,
    required String name,
    required String content,
    required int autoArchiveDurationMinutes,
    List<PendingAttachment> attachments = const [],
    List<String> appliedTagIds = const [],
  }) => _threads.createForumPost(
    channelId: channelId,
    name: name,
    content: content,
    autoArchiveDurationMinutes: autoArchiveDurationMinutes,
    attachments: attachments,
    appliedTagIds: appliedTagIds,
  );
}
