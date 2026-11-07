part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryMemberList
    implements GuildMemberListRepository {
  DiscordDesktopGatewayClient get _gateway;
  DiscordMemberListHandler get _memberLists;

  @override
  Stream<GuildMemberList> get memberListUpdates => _memberLists.updates;

  @override
  String memberListIdFor({
    required String guildId,
    required String channelId,
  }) => _memberLists.memberListIdFor(guildId: guildId, channelId: channelId);

  @override
  GuildMemberList? memberListFor({
    required String guildId,
    required String listId,
  }) => _memberLists.listFor(guildId: guildId, listId: listId);

  @override
  void subscribeMemberRanges({
    required String guildId,
    required String channelId,
    required List<List<int>> ranges,
  }) => _gateway.subscribeMemberRanges(
    guildId: guildId,
    channelId: channelId,
    ranges: ranges,
  );

  @override
  void unsubscribeMemberRanges({
    required String guildId,
    required String channelId,
  }) =>
      _gateway.unsubscribeMemberRanges(guildId: guildId, channelId: channelId);

  @override
  void searchGuildMembers({
    required String guildId,
    required String query,
    int limit = 25,
  }) => _gateway.requestGuildMembers(
    guildId: guildId,
    query: query,
    limit: limit,
  );

  @override
  void requestGuildMembers({
    required String guildId,
    required List<String> userIds,
  }) => _gateway.requestGuildMembersByIds(guildId: guildId, userIds: userIds);
}
