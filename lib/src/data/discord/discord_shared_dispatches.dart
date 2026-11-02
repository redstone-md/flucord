import 'dart:async';

import '../../app_log.dart';
import '../../domain/chat_cache.dart';
import '../../domain/chat_repository.dart';
import 'discord_channel_handler.dart';
import 'discord_direct_messages.dart';
import 'discord_gateway_client.dart';
import 'discord_mapper.dart';
import 'discord_message_update_handler.dart';
import 'discord_reaction_handler.dart';
import 'discord_repository_events.dart';

/// The gateway dispatches that the bot and desktop transports answer the same
/// way.
///
/// Both transports send every dispatch here, so a dispatch added to [route]
/// works on both and the two cannot drift apart. A transport's own routing keeps
/// only what really differs between them.
final class DiscordSharedDispatches {
  DiscordSharedDispatches({
    required ChatCache cache,
    required DiscordMapper mapper,
    required DiscordDirectMessages directMessages,
    required String? Function() currentMemberId,
    required List<Map<String, Object?>> Function(String guildId) rolesOf,
    required StreamController<ChatRepositoryEvent> events,
  }) : _cache = cache,
       _mapper = mapper,
       _directMessages = directMessages,
       _currentMemberId = currentMemberId,
       _rolesOf = rolesOf,
       _events = events,
       _reactions = DiscordReactionHandler(cache, currentMemberId),
       _updates = DiscordMessageUpdateHandler(cache, mapper, currentMemberId),
       _channels = DiscordChannelHandler(cache, mapper, events.publish);

  final ChatCache _cache;
  final DiscordMapper _mapper;
  final DiscordDirectMessages _directMessages;
  final String? Function() _currentMemberId;
  final List<Map<String, Object?>> Function(String guildId) _rolesOf;
  final StreamController<ChatRepositoryEvent> _events;
  final DiscordReactionHandler _reactions;
  final DiscordMessageUpdateHandler _updates;
  final DiscordChannelHandler _channels;

  /// The step added last. See [inOrder].
  Future<void> _lastStep = Future.value();

  /// Finishes when every step added so far has run. A repository closes its
  /// cache only after this, so no step is cut off halfway.
  Future<void> get drained => _lastStep;

  void route(DiscordGatewayDispatch event) {
    switch (event.name) {
      case 'MESSAGE_REACTION_ADD' ||
          'MESSAGE_REACTION_REMOVE' ||
          'MESSAGE_REACTION_REMOVE_EMOJI' ||
          'MESSAGE_REACTION_REMOVE_ALL':
        inOrder(() => _announce(_reactions.apply(event)));
      case 'MESSAGE_UPDATE':
        inOrder(() => _announce(_updates.apply(event.data)));
      case 'MESSAGE_DELETE':
        inOrder(() => _deleteMessage(event.data));
      case 'MESSAGE_DELETE_BULK':
        inOrder(() => _deleteMessages(event.data));
      case 'CHANNEL_CREATE' ||
          'CHANNEL_UPDATE' ||
          'THREAD_CREATE' ||
          'THREAD_UPDATE':
        unawaited(_upsertChannel(event.data));
      case 'CHANNEL_DELETE' || 'THREAD_DELETE':
        unawaited(_channels.delete(event.data));
      case 'CHANNEL_PINS_UPDATE':
        _pinsChanged(event.data);
      case 'GUILD_MEMBER_ADD' || 'GUILD_MEMBER_UPDATE':
        unawaited(_upsertMember(event.data));
      case 'GUILD_MEMBER_REMOVE':
        _removeMember(event.data);
    }
  }

  /// Runs [step] after every step added before it.
  ///
  /// Each dispatch about a message goes through here, because each one waits on
  /// the cache. Run side by side, a slow create or edit would finish after the
  /// delete that followed it and bring the message back. A step that fails is
  /// logged, and the next one still runs.
  void inOrder(Future<void> Function() step) {
    _lastStep = _lastStep.then((_) async {
      try {
        await step();
      } catch (error, stackTrace) {
        AppLog.warning(
          'discord.dispatch',
          'Could not apply a message dispatch: $error ($stackTrace)',
          error: error,
        );
      }
    });
  }

  /// Announces what a handler answered, once the handler has its answer.
  Future<void> _announce(Future<ChatRepositoryEvent?> answer) async {
    final update = await answer;
    if (update != null) _events.publish(update);
  }

  Future<void> _deleteMessage(Map<String, Object?> data) async {
    final messageId = data['id'] as String?;
    final channelId = data['channel_id'] as String?;
    if (messageId == null || channelId == null) return;
    await _cache.deleteMessage(messageId);
    _events.publish(
      MessageDeletedEvent(messageId: messageId, channelId: channelId),
    );
  }

  Future<void> _deleteMessages(Map<String, Object?> data) async {
    final ids = data['ids'];
    final channelId = data['channel_id'] as String?;
    if (ids is! List || channelId == null) return;
    final messageIds = ids.whereType<String>().toSet();
    await Future.wait(messageIds.map(_cache.deleteMessage));
    _events.publish(
      MessagesDeletedEvent(messageIds: messageIds, channelId: channelId),
    );
  }

  Future<void> _upsertChannel(Map<String, Object?> data) async {
    final guildId = data['guild_id'] as String?;
    if (guildId != null) return _channels.upsert(data, guildId);
    final currentUserId = _currentMemberId();
    if (currentUserId != null) {
      await _directMessages.acceptChannel(data, currentUserId);
    }
  }

  void _pinsChanged(Map<String, Object?> data) {
    final channelId = data['channel_id'] as String?;
    if (channelId != null) _events.publish(PinsChangedEvent(channelId));
  }

  Future<void> _upsertMember(Map<String, Object?> data) async {
    final guildId = data['guild_id'] as String?;
    if (guildId == null || data['user'] is! Map) return;
    final member = _mapper.guildMember(data, guildId, _rolesOf(guildId));
    _events.publish(MemberUpsertedEvent(member));
    await _cache.writeMember(member);
  }

  void _removeMember(Map<String, Object?> data) {
    final guildId = data['guild_id'] as String?;
    final user = data['user'];
    final memberId = user is Map ? user['id'] as String? : null;
    if (guildId == null || memberId == null) return;
    _events.publish(MemberRemovedEvent(memberId: memberId, spaceId: guildId));
  }
}
