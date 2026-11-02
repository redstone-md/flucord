import 'chat_models.dart';
import 'reaction_repository.dart';

/// One change to the reactions on a message.
///
/// It describes the change, not the result, because the workspace and the cache
/// each hold their own copy of the message and either may lack it. The cache
/// prunes old messages that the workspace can still show, so each copy applies
/// the change for itself.
sealed class MessageReactionChange {
  const MessageReactionChange({
    required this.channelId,
    required this.messageId,
  });

  final String channelId;
  final String messageId;

  /// [message] with this change applied.
  ChatMessage applyTo(ChatMessage message) =>
      message.copyWith(reactions: _applied(message.reactions));

  List<MessageReaction> _applied(List<MessageReaction> reactions);
}

/// One person added or took back one reaction.
final class MessageReactionCounted extends MessageReactionChange {
  const MessageReactionCounted({
    required super.channelId,
    required super.messageId,
    required this.emojiName,
    required this.emojiId,
    required this.animated,
    required this.added,
    required this.byCurrentUser,
    required this.type,
    required this.burstColors,
  });

  final String emojiName;
  final String? emojiId;
  final bool animated;
  final bool added;
  final bool byCurrentUser;
  final DiscordReactionType type;
  final List<int> burstColors;

  @override
  List<MessageReaction> _applied(List<MessageReaction> reactions) {
    final index = reactions.indexWhere(
      (reaction) =>
          reaction.emojiName == emojiName && reaction.emojiId == emojiId,
    );
    if (index < 0) {
      return added ? [...reactions, _first()] : reactions;
    }
    final updated = _counted(reactions[index]);
    return [...reactions.take(index), ?updated, ...reactions.skip(index + 1)];
  }

  MessageReaction _first() => MessageReaction(
    emojiName: emojiName,
    emojiId: emojiId,
    animated: animated,
    count: 1,
    normalCount: type == DiscordReactionType.normal ? 1 : 0,
    burstCount: type == DiscordReactionType.burst ? 1 : 0,
    reactedByCurrentUser: type == DiscordReactionType.normal && byCurrentUser,
    burstByCurrentUser: type == DiscordReactionType.burst && byCurrentUser,
    burstColorValues: burstColors,
  );

  /// [current] with this change counted, or null when nobody is left on it.
  MessageReaction? _counted(MessageReaction current) {
    final delta = added ? 1 : -1;
    final count = current.count + delta;
    if (count <= 0) return null;
    final normalDelta = type == DiscordReactionType.normal ? delta : 0;
    final burstDelta = type == DiscordReactionType.burst ? delta : 0;
    final burstCount = (current.burstCount + burstDelta)
        .clamp(0, count)
        .toInt();
    return current.copyWith(
      count: count,
      normalCount: (current.normalCount + normalDelta).clamp(0, count).toInt(),
      burstCount: burstCount,
      reactedByCurrentUser: byCurrentUser && type == DiscordReactionType.normal
          ? added
          : current.reactedByCurrentUser,
      burstByCurrentUser: byCurrentUser && type == DiscordReactionType.burst
          ? added
          : current.burstByCurrentUser,
      burstColorValues: burstCount == 0
          ? const []
          : burstColors.isEmpty
          ? current.burstColorValues
          : burstColors,
    );
  }
}

/// A moderator cleared one emoji from the message.
final class MessageReactionEmojiCleared extends MessageReactionChange {
  const MessageReactionEmojiCleared({
    required super.channelId,
    required super.messageId,
    required this.emojiName,
    required this.emojiId,
  });

  final String emojiName;
  final String? emojiId;

  @override
  List<MessageReaction> _applied(List<MessageReaction> reactions) => [
    for (final reaction in reactions)
      if (reaction.emojiName != emojiName || reaction.emojiId != emojiId)
        reaction,
  ];
}

/// A moderator cleared every reaction from the message.
final class MessageReactionsCleared extends MessageReactionChange {
  const MessageReactionsCleared({
    required super.channelId,
    required super.messageId,
  });

  @override
  List<MessageReaction> _applied(List<MessageReaction> reactions) => const [];
}
