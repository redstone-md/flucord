import '../../domain/chat_cache.dart';
import '../../domain/chat_repository.dart';
import '../../domain/message_reaction_change.dart';
import '../../domain/reaction_repository.dart';
import 'discord_color.dart';
import 'discord_gateway_client.dart';

/// Turns reaction dispatches into a change for the workspace and the cache.
final class DiscordReactionHandler {
  DiscordReactionHandler(this._cache, this._currentMemberId, this._publish);

  final ChatCache _cache;
  final String? Function() _currentMemberId;
  final void Function(ChatRepositoryEvent event) _publish;

  /// Announces [event], then applies it to the cached message, if there is one.
  /// A payload that describes no change does nothing.
  Future<void> apply(DiscordGatewayDispatch event) async {
    final change = _changeFrom(event);
    if (change == null) return;
    _publish(MessageReactionChangedEvent(change));
    await _cache.updateMessage(change.messageId, change.applyTo);
  }

  MessageReactionChange? _changeFrom(DiscordGatewayDispatch event) {
    final channelId = event.data['channel_id'];
    final messageId = event.data['message_id'];
    if (channelId is! String || messageId is! String) return null;
    if (event.name == 'MESSAGE_REACTION_REMOVE_ALL') {
      return MessageReactionsCleared(
        channelId: channelId,
        messageId: messageId,
      );
    }
    if (event.name == 'MESSAGE_REACTION_ADD_MANY') {
      return _batchFrom(event.data, channelId, messageId);
    }
    final emoji = _emojiFrom(event.data['emoji']);
    if (emoji == null) return null;
    if (event.name == 'MESSAGE_REACTION_REMOVE_EMOJI') {
      return MessageReactionEmojiCleared(
        channelId: channelId,
        messageId: messageId,
        emojiName: emoji.name,
        emojiId: emoji.id,
      );
    }
    return MessageReactionCounted(
      channelId: channelId,
      messageId: messageId,
      emojiName: emoji.name,
      emojiId: emoji.id,
      animated: emoji.animated,
      added: event.name == 'MESSAGE_REACTION_ADD',
      byCurrentUser: event.data['user_id'] == _currentMemberId(),
      type: event.data['type'] == DiscordReactionType.burst.discordValue
          ? DiscordReactionType.burst
          : DiscordReactionType.normal,
      burstColors: (event.data['burst_colors'] as List? ?? const [])
          .whereType<String>()
          .map(DiscordColor.parseHex)
          .whereType<int>()
          .toList(growable: false),
    );
  }

  /// `MESSAGE_REACTION_ADD_MANY`: Discord folds a quick run of added reactions
  /// into one dispatch, listing who reacted with each emoji. It names no type,
  /// so each one counts as a normal reaction.
  MessageReactionBatch? _batchFrom(
    Map<String, Object?> data,
    String channelId,
    String messageId,
  ) {
    final currentMemberId = _currentMemberId();
    final changes = [
      for (final entry
          in (data['reactions'] as List? ?? const []).whereType<Map>())
        if (_emojiFrom(entry['emoji']) case final emoji?)
          for (final userId in (entry['users'] as List? ?? const []))
            MessageReactionCounted(
              channelId: channelId,
              messageId: messageId,
              emojiName: emoji.name,
              emojiId: emoji.id,
              animated: emoji.animated,
              added: true,
              byCurrentUser: userId == currentMemberId,
              type: DiscordReactionType.normal,
              burstColors: const [],
            ),
    ];
    if (changes.isEmpty) return null;
    return MessageReactionBatch(
      channelId: channelId,
      messageId: messageId,
      changes: changes,
    );
  }

  /// The partial emoji a reaction dispatch carries, or null when it has no
  /// name to match a reaction by.
  ({String name, String? id, bool animated})? _emojiFrom(Object? payload) {
    if (payload is! Map) return null;
    final name = payload['name'];
    if (name is! String) return null;
    return (
      name: name,
      id: payload['id'] as String?,
      animated: payload['animated'] as bool? ?? false,
    );
  }
}
