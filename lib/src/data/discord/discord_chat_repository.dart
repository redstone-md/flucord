import 'dart:async';

import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import 'discord_api_client.dart';
import 'discord_gateway_client.dart';
import 'discord_mapper.dart';

final class DiscordChatRepository implements ChatRepository {
  DiscordChatRepository(
    this._api,
    this._gateway,
    this._cache, {
    DiscordMapper? mapper,
  }) : _mapper = mapper ?? DiscordMapper() {
    _gatewaySubscription = _gateway.events.listen(_onGatewayEvent);
  }

  final DiscordApiClient _api;
  final DiscordGatewayClient _gateway;
  final ChatCache _cache;
  final DiscordMapper _mapper;
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();
  late final StreamSubscription<DiscordGatewayEvent> _gatewaySubscription;

  @override
  Stream<ChatRepositoryEvent> get events => _events.stream;

  @override
  Future<ChatWorkspace> loadWorkspace() async {
    _emitStatus(RepositoryConnectionStatus.connecting);
    try {
      final user = await _api.getCurrentUser();
      final guilds = await _api.getCurrentUserGuilds();
      final channelsByGuild = <String, List<Map<String, Object?>>>{};
      for (final guild in guilds) {
        final guildId = guild['id']! as String;
        channelsByGuild[guildId] = await _api.getGuildChannels(guildId);
      }
      final workspace = _mapper.workspace(
        currentUser: user,
        guilds: guilds,
        channelsByGuild: channelsByGuild,
      );
      await _cache.writeWorkspace(workspace);
      final gatewayUrl = await _api.getGatewayUrl();
      unawaited(_gateway.connect(gatewayUrl));
      return workspace;
    } catch (error) {
      if (error is DiscordApiException && error.isUnauthorized) rethrow;
      final cached = await _cache.readWorkspace();
      if (cached != null) {
        _emitStatus(RepositoryConnectionStatus.offline);
        return cached;
      }
      rethrow;
    }
  }

  @override
  Future<ChannelHistory> loadChannelHistory(String channelId) async {
    try {
      final payloads = await _api.getChannelMessages(channelId);
      final history = _mapper.history(channelId, payloads);
      await _cache.writeChannelHistory(history);
      return history;
    } catch (error) {
      if (error is DiscordApiException && error.isUnauthorized) rethrow;
      final cached = await _cache.readChannelHistory(channelId);
      if (cached.messages.isNotEmpty) return cached;
      rethrow;
    }
  }

  @override
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
  }) async {
    final payload = await _api.createMessage(
      channelId: channelId,
      content: body,
    );
    final message = _mapper.message(payload);
    await _cache.writeMessage(message);
    return message;
  }

  void _onGatewayEvent(DiscordGatewayEvent event) {
    switch (event) {
      case DiscordGatewayStatusEvent():
        _emitStatus(switch (event.status) {
          DiscordGatewayStatus.offline => RepositoryConnectionStatus.offline,
          DiscordGatewayStatus.connecting =>
            RepositoryConnectionStatus.connecting,
          DiscordGatewayStatus.connected =>
            RepositoryConnectionStatus.connected,
          DiscordGatewayStatus.reconnecting =>
            RepositoryConnectionStatus.reconnecting,
        });
      case DiscordGatewayDispatch():
        if (event.name != 'MESSAGE_CREATE' && event.name != 'MESSAGE_UPDATE') {
          return;
        }
        unawaited(_handleMessageDispatch(event));
    }
  }

  Future<void> _handleMessageDispatch(DiscordGatewayDispatch event) async {
    final messageId = event.data['id'] as String?;
    if (messageId == null) return;
    final fallback = event.name == 'MESSAGE_UPDATE'
        ? await _cache.readMessage(messageId)
        : null;
    if (event.name == 'MESSAGE_UPDATE' && fallback == null) return;
    final message = _mapper.message(event.data, fallback: fallback);
    final authorPayload = event.data['author'];
    final member = authorPayload is Map
        ? _mapper.member(authorPayload.cast<String, Object?>())
        : null;
    await _cache.writeMessage(message, member: member);
    if (!_events.isClosed) {
      _events.add(MessageUpsertedEvent(message: message, member: member));
    }
  }

  void _emitStatus(RepositoryConnectionStatus status) {
    if (!_events.isClosed) {
      _events.add(RepositoryStatusChangedEvent(status));
    }
  }

  @override
  Future<void> close() async {
    await _gatewaySubscription.cancel();
    await _gateway.close();
    _api.close();
    await _cache.close();
    await _events.close();
  }
}
