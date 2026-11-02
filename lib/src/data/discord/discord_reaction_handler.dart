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
    final emojiPayload = event.data['emoji'];
    if (emojiPayload is! Map) return null;
    final emoji = emojiPayload.cast<String, Object?>();
    final name = emoji['name'] as String?;
    if (name == null) return null;
    final id = emoji['id'] as String?;
    if (event.name == 'MESSAGE_REACTION_REMOVE_EMOJI') {
      return MessageReactionEmojiCleared(
        channelId: channelId,
        messageId: messageId,
        emojiName: name,
        emojiId: id,
      );
    }
    return MessageReactionCounted(
      channelId: channelId,
      messageId: messageId,
      emojiName: name,
      emojiId: id,
      animated: emoji['animated'] as bool? ?? false,
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
}
