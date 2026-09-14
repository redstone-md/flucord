import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import 'discord_api_client.dart';
import 'discord_mapper.dart';

final class DiscordDirectMessages {
  DiscordDirectMessages(this._api, this._cache, this._mapper);

  final DiscordApiClient _api;
  final ChatCache _cache;
  final DiscordMapper _mapper;
  final Set<String> _knownChannelIds = {};

  CommunitySpace get space => _mapper.directMessagesSpace;

  void seed(Iterable<ConversationChannel> channels) {
    _knownChannelIds.addAll(
      channels
          .where((channel) => channel.isDirectMessage)
          .map((channel) => channel.id),
    );
  }

  Future<DirectConversation> open(
    String recipientId,
    String currentUserId,
  ) async {
    final payload = await _api.createDirectMessageChannel(recipientId);
    final mapped = _mapper.directMessage(payload, currentUserId);
    if (mapped == null) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Discord returned an invalid direct message channel',
      );
    }
    return _persist(mapped);
  }

  Future<DirectConversation?> acceptChannel(
    Map<String, Object?> payload,
    String currentUserId,
  ) async {
    final mapped = _mapper.directMessage(payload, currentUserId);
    return mapped == null ? null : _persist(mapped);
  }

  Future<DirectConversation?> acceptMessage(
    Map<String, Object?> payload,
    String currentUserId,
  ) async {
    if (payload['guild_id'] != null) return null;
    final channelId = payload['channel_id'] as String?;
    if (channelId == null || _knownChannelIds.contains(channelId)) return null;
    final channelType = payload['channel_type'];
    if (channelType != null && channelType != 1) return null;
    final author = payload['author'];
    if (author is! Map || author['id'] == currentUserId) return null;
    return acceptChannel({
      'id': channelId,
      'type': 1,
      'recipients': [author],
    }, currentUserId);
  }

  Future<DirectConversation> _persist(DiscordMappedDirectMessage mapped) async {
    final conversation = DirectConversation(
      channel: mapped.channel,
      recipient: mapped.recipient,
    );
    _knownChannelIds.add(conversation.channel.id);
    await _cache.writeSpace(space);
    await _cache.writeChannel(conversation.channel);
    await _cache.writeMember(conversation.recipient);
    return conversation;
  }
}
