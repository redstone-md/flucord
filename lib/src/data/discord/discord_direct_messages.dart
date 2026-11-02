import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import 'discord_mapper.dart';
import 'discord_rest_client.dart';

/// Direct message channels the account gains, on either transport.
///
/// A conversation is announced before it is written, for the reason
/// `DiscordChannelHandler` gives: the first message must find its channel in
/// the workspace.
final class DiscordDirectMessages {
  DiscordDirectMessages(
    this._createChannel,
    this._cache,
    this._mapper,
    this._publish, {
    void Function(String channelId)? onChannelAdded,
  }) : _onChannelAdded = onChannelAdded;

  /// The transport's own route for opening a channel with somebody.
  final Future<Map<String, Object?>> Function(String recipientId)
  _createChannel;
  final ChatCache _cache;
  final DiscordMapper _mapper;
  final void Function(ChatRepositoryEvent event) _publish;
  final void Function(String channelId)? _onChannelAdded;
  final Set<String> _knownChannelIds = {};

  CommunitySpace get _space => _mapper.directMessagesSpace;

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
    final payload = await _createChannel(recipientId);
    final mapped = _mapper.directMessage(payload, currentUserId);
    if (mapped == null) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Discord returned an invalid direct message channel',
      );
    }
    return _adopt(mapped);
  }

  Future<void> acceptChannel(
    Map<String, Object?> payload,
    String currentUserId,
  ) async {
    final mapped = _mapper.directMessage(payload, currentUserId);
    if (mapped != null) await _adopt(mapped);
  }

  /// Adopts the channel of a message when the channel is new here.
  ///
  /// `MESSAGE_CREATE` is sometimes the first the client hears of a DM. The
  /// message's author is then the only recipient it can name.
  Future<void> acceptMessage(
    Map<String, Object?> payload,
    String currentUserId,
  ) async {
    if (payload['guild_id'] != null) return;
    final channelId = payload['channel_id'] as String?;
    if (channelId == null || _knownChannelIds.contains(channelId)) return;
    final channelType = payload['channel_type'];
    if (channelType != null && channelType != 1) return;
    final author = payload['author'];
    if (author is! Map || author['id'] == currentUserId) return;
    await acceptChannel({
      'id': channelId,
      'type': 1,
      'recipients': [author],
    }, currentUserId);
  }

  Future<DirectConversation> _adopt(DiscordMappedDirectMessage mapped) async {
    final conversation = DirectConversation(
      channel: mapped.channel,
      recipient: mapped.recipient,
    );
    if (_knownChannelIds.add(conversation.channel.id)) {
      _onChannelAdded?.call(conversation.channel.id);
    }
    _publish(SpaceUpsertedEvent(_space));
    _publish(MemberUpsertedEvent(conversation.recipient));
    _publish(ChannelUpsertedEvent(conversation.channel));
    await _cache.writeSpace(_space);
    await _cache.writeChannel(conversation.channel);
    await _cache.writeMember(conversation.recipient);
    return conversation;
  }
}
