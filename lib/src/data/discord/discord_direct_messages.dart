import '../../app_log.dart';
import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import 'discord_mapper.dart';
import 'discord_rest_client.dart';

/// DMs the account gains or changes, on either transport.
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

  /// The newest Discord payload of each DM, by channel id.
  ///
  /// A recipient event names only the channel and the user, so a group DM is
  /// rebuilt from this payload: its own name and every other recipient.
  final Map<String, Map<String, Object?>> _payloads = {};

  CommunitySpace get _space => _mapper.directMessagesSpace;

  /// The DMs the account holds after a READY or an offline launch.
  ///
  /// [channels] replace what was known: a DM closed while the client was
  /// away must be new again, so that its next message brings it back.
  /// [payloads] are the private channels the READY carried, with their
  /// recipients expanded. An offline launch has none.
  void seed(
    Iterable<ConversationChannel> channels, {
    Iterable<Map<String, Object?>> payloads = const [],
  }) {
    _knownChannelIds
      ..clear()
      ..addAll(
        channels
            .where((channel) => channel.isDirectMessage)
            .map((channel) => channel.id),
      );
    _payloads
      ..clear()
      ..addEntries([
        for (final payload in payloads)
          if (payload['id'] case final String id) MapEntry(id, payload),
      ]);
  }

  Future<DirectConversation> open(
    String recipientId,
    String currentUserId,
  ) async {
    final payload = await _createChannel(recipientId);
    final conversation = _mapper.directMessage(payload, currentUserId);
    if (conversation == null) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Discord returned an invalid direct message channel',
      );
    }
    return _adopt(conversation, payload);
  }

  Future<void> acceptChannel(
    Map<String, Object?> payload,
    String currentUserId,
  ) async {
    final conversation = _mapper.directMessage(payload, currentUserId);
    if (conversation != null) await _adopt(conversation, payload);
  }

  /// Applies `CHANNEL_RECIPIENT_ADD` or `CHANNEL_RECIPIENT_REMOVE` to a group
  /// DM, which renames a group that has no name of its own.
  Future<void> acceptRecipientChange(
    Map<String, Object?> data,
    String currentUserId, {
    required bool added,
  }) async {
    final channelId = data['channel_id'];
    final user = data['user'];
    if (channelId is! String || user is! Map) return;
    final payload = _payloads[channelId];
    if (payload == null) {
      AppLog.warning(
        'discord.dm',
        'A recipient changed in DM $channelId, which this session never '
            'received; the list catches up on the next READY.',
      );
      return;
    }
    final others = (payload['recipients'] as List? ?? const [])
        .whereType<Map>()
        .where((recipient) => recipient['id'] != user['id']);
    await acceptChannel({
      ...payload,
      'recipients': [...others, if (added) user],
    }, currentUserId);
  }

  /// Forgets a DM the account closed or a group it left, so that a late
  /// recipient event cannot rebuild it and its next message or
  /// `CHANNEL_CREATE` adds it again.
  void forget(String channelId) {
    _knownChannelIds.remove(channelId);
    _payloads.remove(channelId);
  }

  /// Adopts the channel of a message when the channel is new here.
  ///
  /// `MESSAGE_CREATE` is sometimes the first the client hears of a one-to-one
  /// DM. The message's author is then the only recipient it can name. A group
  /// DM cannot be rebuilt from a message, which names neither the group nor
  /// its other recipients; Discord sends `CHANNEL_CREATE` for a new group
  /// before its first message.
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

  Future<DirectConversation> _adopt(
    DirectConversation conversation,
    Map<String, Object?> payload,
  ) async {
    final channel = conversation.channel;
    _payloads[channel.id] = payload;
    if (_knownChannelIds.add(channel.id)) {
      _onChannelAdded?.call(channel.id);
    }
    _publish(SpaceUpsertedEvent(_space));
    conversation.recipients.map(MemberUpsertedEvent.new).forEach(_publish);
    _publish(ChannelUpsertedEvent(channel));
    // Asked for together, with no wait in between, so that these reach the cache
    // ahead of the message that brought the channel, in the same flush.
    await Future.wait([
      _cache.writeSpace(_space),
      _cache.writeChannel(channel),
      ...conversation.recipients.map(_cache.writeMember),
    ]);
    return conversation;
  }
}
