import 'dart:async';

import '../../app_log.dart';
import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import 'discord_channel_handler.dart';
import 'discord_direct_messages.dart';
import 'discord_gateway_client.dart';
import 'discord_mapper.dart';
import 'discord_message_update_handler.dart';
import 'discord_reaction_handler.dart';
import 'discord_repository_events.dart';
import 'discord_role_dispatch.dart';

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
    required DiscordUpdatedMessage updatedMessage,
    required StreamController<ChatRepositoryEvent> events,
  }) : _cache = cache,
       _mapper = mapper,
       _directMessages = directMessages,
       _currentMemberId = currentMemberId,
       _events = events,
       _reactions = DiscordReactionHandler(
         cache,
         currentMemberId,
         events.publish,
       ),
       _updates = DiscordMessageUpdateHandler(
         cache,
         mapper,
         updatedMessage,
         events.publish,
       ),
       _channels = DiscordChannelHandler(cache, mapper, events.publish);

  final ChatCache _cache;
  final DiscordMapper _mapper;
  final DiscordDirectMessages _directMessages;
  final String? Function() _currentMemberId;
  final StreamController<ChatRepositoryEvent> _events;
  final DiscordReactionHandler _reactions;
  final DiscordMessageUpdateHandler _updates;
  final DiscordChannelHandler _channels;

  /// The step added last. See [inOrder].
  Future<void> _lastStep = Future.value();

  /// The start of a repository's close. No dispatch comes in after it, every
  /// step queued so far runs to its end, so none meets a closed cache, and the
  /// cache writes what is waiting, before a slow socket further down the close
  /// can cost it.
  Future<void> stop(StreamSubscription<DiscordGatewayEvent> gateway) async {
    await gateway.cancel();
    await _lastStep;
    await _cache.flush();
  }

  /// A `MESSAGE_CREATE`, on the message queue. Each transport reads the message
  /// its own way with [read]. [beforeAnnounce] runs right before the message is
  /// announced, with nothing awaited between them.
  void acceptNewMessage(
    Map<String, Object?> payload, {
    required ChatMessage Function(Map<String, Object?> payload) read,
    void Function()? beforeAnnounce,
  }) => inOrder(() async {
    if (payload['id'] is! String) return;
    final message = read(payload);
    final member = _mapper.messageAuthor(payload);
    final mentioned = _mapper.mentionedMembers(payload);
    final currentUserId = _currentMemberId();
    // A new channel is announced and queued here, ahead of the message.
    final channelAdopted = currentUserId == null
        ? null
        : _directMessages.acceptMessage(payload, currentUserId);
    // Ahead of the message, so its mentions read right when it is drawn.
    if (mentioned.isNotEmpty) _events.publish(MembersUpsertedEvent(mentioned));
    beforeAnnounce?.call();
    _events.publish(
      MessageUpsertedEvent(
        message: message,
        member: member,
        isNew: true,
        mentionsCurrentMember: message.mentionsCurrentMember,
      ),
    );
    await _cache.writeMessage(message, member: member);
    await _cache.writeMembers(mentioned);
    await channelAdopted;
  });

  void route(DiscordGatewayDispatch event) {
    switch (event.name) {
      case 'MESSAGE_REACTION_ADD' ||
          'MESSAGE_REACTION_ADD_MANY' ||
          'MESSAGE_REACTION_REMOVE' ||
          'MESSAGE_REACTION_REMOVE_EMOJI' ||
          'MESSAGE_REACTION_REMOVE_ALL':
        inOrder(() => _reactions.apply(event));
      case 'MESSAGE_UPDATE':
        inOrder(() => _updates.apply(event.data));
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
        _forgetDirectMessage(event.data);
        unawaited(_channels.delete(event.data));
      case 'CHANNEL_RECIPIENT_ADD':
        unawaited(_recipientChanged(event.data, added: true));
      case 'CHANNEL_RECIPIENT_REMOVE':
        unawaited(_recipientChanged(event.data, added: false));
      case 'CHANNEL_PINS_UPDATE':
        _pinsChanged(event.data);
      case 'GUILD_MEMBER_ADD' || 'GUILD_MEMBER_UPDATE':
        unawaited(_upsertMember(event.data));
      case 'GUILD_MEMBER_REMOVE':
        _removeMember(event.data);
      case 'GUILD_ROLE_CREATE' || 'GUILD_ROLE_UPDATE' || 'GUILD_ROLE_DELETE':
        if (DiscordRoleDispatch.read(event.name, event.data)
            case final change?) {
          unawaited(_changeRole(change));
        }
      case 'PRESENCE_UPDATE':
        unawaited(_presenceIdentity(event.data));
    }
  }

  /// Runs [step] after every step added before it.
  ///
  /// Each dispatch about a message goes through here, so that nothing overtakes
  /// a step that has to wait, such as a poll vote reading its message. A step
  /// announces first and writes after, and the cache applies its writes in the
  /// order they came, so a delete has the last word. A step that fails is logged,
  /// and the next one still runs.
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

  Future<void> _deleteMessage(Map<String, Object?> data) async {
    final messageId = data['id'] as String?;
    final channelId = data['channel_id'] as String?;
    if (messageId == null || channelId == null) return;
    _events.publish(
      MessageDeletedEvent(messageId: messageId, channelId: channelId),
    );
    await _cache.deleteMessage(messageId);
  }

  Future<void> _deleteMessages(Map<String, Object?> data) async {
    final ids = data['ids'];
    final channelId = data['channel_id'] as String?;
    if (ids is! List || channelId == null) return;
    final messageIds = ids.whereType<String>().toSet();
    _events.publish(
      MessagesDeletedEvent(messageIds: messageIds, channelId: channelId),
    );
    await Future.wait(messageIds.map(_cache.deleteMessage));
  }

  Future<void> _upsertChannel(Map<String, Object?> data) async {
    final guildId = data['guild_id'] as String?;
    if (guildId != null) return _channels.upsert(data, guildId);
    final currentUserId = _currentMemberId();
    if (currentUserId != null) {
      await _directMessages.acceptChannel(data, currentUserId);
    }
  }

  void _forgetDirectMessage(Map<String, Object?> data) {
    final id = data['id'];
    if (data['guild_id'] == null && id is String) _directMessages.forget(id);
  }

  Future<void> _recipientChanged(
    Map<String, Object?> data, {
    required bool added,
  }) async {
    final currentUserId = _currentMemberId();
    if (currentUserId == null) return;
    await _directMessages.acceptRecipientChange(
      data,
      currentUserId,
      added: added,
    );
  }

  void _pinsChanged(Map<String, Object?> data) {
    final channelId = data['channel_id'] as String?;
    if (channelId != null) _events.publish(PinsChangedEvent(channelId));
  }

  Future<void> _upsertMember(Map<String, Object?> data) async {
    final guildId = data['guild_id'] as String?;
    if (guildId == null || data['user'] is! Map) return;
    final member = _mapper.guildMember(data, guildId);
    _events.publish(MemberUpsertedEvent(member));
    await _cache.writeMember(member);
  }

  /// The username and tags on a presence's user. Most presences name the
  /// user by id alone, which says nothing about either; only a whole user,
  /// one with a username, does.
  Future<void> _presenceIdentity(Map<String, Object?> data) async {
    final user = data['user'];
    if (user is! Map) return;
    final memberId = user['id'];
    final identity = _mapper.identity(user.cast<String, Object?>());
    if (memberId is! String || identity == null) return;
    _events.publish(
      MemberIdentityChangedEvent(memberId: memberId, identity: identity),
    );
    await _cache.writeMemberIdentity(memberId, identity);
  }

  Future<void> _changeRole(DiscordRoleDispatch change) async {
    final role = change.role;
    if (role == null) {
      _events.publish(RoleDeletedEvent(change.roleId));
      return _cache.deleteRole(change.roleId);
    }
    final mapped = _mapper.role(role, change.guildId);
    _events.publish(RoleUpsertedEvent(mapped));
    await _cache.writeRole(mapped);
  }

  void _removeMember(Map<String, Object?> data) {
    final guildId = data['guild_id'] as String?;
    final user = data['user'];
    final memberId = user is Map ? user['id'] as String? : null;
    if (guildId == null || memberId == null) return;
    _events.publish(MemberRemovedEvent(memberId: memberId, spaceId: guildId));
  }
}
