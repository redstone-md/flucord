part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryReadState {
  ChatCache get _cache;
  DiscordReadStateRepository get _readState;

  /// Read state is account state on the user's own session: `READY` carries
  /// it, this socket receives every later revision of it, and these
  /// credentials are the only ones allowed to acknowledge one.
  ReadStateRepository? get readState => _readState;

  Future<void> saveChannelActivity(ConversationChannel channel) =>
      _cache.writeChannelActivity(channel);
}
