import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../domain/reaction_repository.dart';
import 'discord_color.dart';
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
    final type = event.data['type'] == DiscordReactionType.burst.discordValue
        ? DiscordReactionType.burst
        : DiscordReactionType.normal;
    final burstColors = (event.data['burst_colors'] as List? ?? const [])
        .whereType<String>()
        .map(DiscordColor.parseHex)
        .whereType<int>()
        .toList(growable: false);
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
          normalCount: type == DiscordReactionType.normal ? 1 : 0,
          burstCount: type == DiscordReactionType.burst ? 1 : 0,
          reactedByCurrentUser:
              type == DiscordReactionType.normal && byCurrentUser,
          burstByCurrentUser:
              type == DiscordReactionType.burst && byCurrentUser,
          burstColorValues: burstColors,
        ),
      );
    } else if (index >= 0) {
      _updateExisting(reactions, index, add, byCurrentUser, type, burstColors);
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
    DiscordReactionType type,
    List<int> burstColors,
  ) {
    final current = reactions[index];
    final count = current.count + (add ? 1 : -1);
    if (count <= 0) {
      reactions.removeAt(index);
      return;
    }
    final normalDelta = type == DiscordReactionType.normal ? (add ? 1 : -1) : 0;
    final burstDelta = type == DiscordReactionType.burst ? (add ? 1 : -1) : 0;
    final burstCount = (current.burstCount + burstDelta)
        .clamp(0, count)
        .toInt();
    reactions[index] = current.copyWith(
      count: count,
      normalCount: (current.normalCount + normalDelta).clamp(0, count).toInt(),
      burstCount: burstCount,
      reactedByCurrentUser: byCurrentUser && type == DiscordReactionType.normal
          ? add
          : current.reactedByCurrentUser,
      burstByCurrentUser: byCurrentUser && type == DiscordReactionType.burst
          ? add
          : current.burstByCurrentUser,
      burstColorValues: burstCount == 0
          ? const []
          : burstColors.isEmpty
          ? current.burstColorValues
          : burstColors,
    );
  }
}
