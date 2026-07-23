import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import 'discord_gateway_client.dart';

final class DiscordReactionHandler {
  const DiscordReactionHandler(this._cache, this._currentMemberId);

  final ChatCache _cache;
  final String? Function() _currentMemberId;

  Future<MessageUpsertedEvent?> apply(DiscordGatewayDispatch event) async {
    final messageId = event.data['message_id'] as String?;
    final emojiPayload = event.data['emoji'];
    if (messageId == null || emojiPayload is! Map) return null;
    final message = await _cache.readMessage(messageId);
    if (message == null) return null;
    final emoji = emojiPayload.cast<String, Object?>();
    final name = emoji['name'] as String?;
    if (name == null) return null;
    final id = emoji['id'] as String?;
    final key = id == null ? name : '$name:$id';
    final add = event.name == 'MESSAGE_REACTION_ADD';
    final byCurrentUser = event.data['user_id'] == _currentMemberId();
    final reactions = [...message.reactions];
    final index = reactions.indexWhere((reaction) => reaction.key == key);
    if (index < 0 && add) {
      reactions.add(
        MessageReaction(
          emojiName: name,
          emojiId: id,
          animated: emoji['animated'] as bool? ?? false,
          count: 1,
          reactedByCurrentUser: byCurrentUser,
        ),
      );
    } else if (index >= 0) {
      _updateExisting(reactions, index, add, byCurrentUser);
    }
    final updated = message.copyWith(reactions: reactions);
    await _cache.writeMessage(updated);
    return MessageUpsertedEvent(message: updated);
  }

  static void _updateExisting(
    List<MessageReaction> reactions,
    int index,
    bool add,
    bool byCurrentUser,
  ) {
    final current = reactions[index];
    final count = current.count + (add ? 1 : -1);
    if (count <= 0) {
      reactions.removeAt(index);
      return;
    }
    reactions[index] = current.copyWith(
      count: count,
      reactedByCurrentUser: byCurrentUser ? add : current.reactedByCurrentUser,
    );
  }
}
