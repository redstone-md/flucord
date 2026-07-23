part of 'chat_models.dart';

final class MessageAttachment {
  const MessageAttachment({
    required this.id,
    required this.fileName,
    required this.url,
    required this.size,
    this.contentType,
    this.width,
    this.height,
  });

  final String id;
  final String fileName;
  final String url;
  final int size;
  final String? contentType;
  final int? width;
  final int? height;

  bool get isImage => contentType?.startsWith('image/') ?? false;

  bool get isVideo {
    if (contentType?.startsWith('video/') ?? false) return true;
    final path = fileName.toLowerCase();
    return const ['.mp4', '.mov', '.webm', '.mkv'].any(path.endsWith);
  }
}

final class MessageReply {
  const MessageReply({
    required this.messageId,
    required this.authorId,
    required this.body,
  });

  final String messageId;
  final String authorId;
  final String body;
}

final class MessageReaction {
  const MessageReaction({
    required this.emojiName,
    required this.count,
    this.emojiId,
    this.animated = false,
    this.reactedByCurrentUser = false,
  });

  final String emojiName;
  final String? emojiId;
  final int count;
  final bool animated;
  final bool reactedByCurrentUser;

  String get key => emojiId == null ? emojiName : '$emojiName:$emojiId';

  MessageReaction copyWith({int? count, bool? reactedByCurrentUser}) =>
      MessageReaction(
        emojiName: emojiName,
        emojiId: emojiId,
        count: count ?? this.count,
        animated: animated,
        reactedByCurrentUser: reactedByCurrentUser ?? this.reactedByCurrentUser,
      );
}

final class ChatMessage {
  ChatMessage({
    required this.id,
    required this.channelId,
    required this.authorId,
    required this.body,
    required this.sentAt,
    List<MessageAttachment> attachments = const [],
    List<MessageEmbed> embeds = const [],
    List<MessageReaction> reactions = const [],
    this.reply,
    this.isEdited = false,
    this.isPinned = false,
    this.mentionsCurrentMember = false,
  }) : attachments = List.unmodifiable(attachments),
       embeds = List.unmodifiable(embeds),
       reactions = List.unmodifiable(reactions);

  final String id;
  final String channelId;
  final String authorId;
  final String body;
  final DateTime sentAt;
  final List<MessageAttachment> attachments;
  final List<MessageEmbed> embeds;
  final MessageReply? reply;
  final List<MessageReaction> reactions;
  final bool isEdited;
  final bool isPinned;
  final bool mentionsCurrentMember;

  ChatMessage copyWith({
    String? body,
    List<MessageAttachment>? attachments,
    List<MessageEmbed>? embeds,
    List<MessageReaction>? reactions,
    bool? isEdited,
    bool? isPinned,
    bool? mentionsCurrentMember,
  }) => ChatMessage(
    id: id,
    channelId: channelId,
    authorId: authorId,
    body: body ?? this.body,
    sentAt: sentAt,
    attachments: attachments ?? this.attachments,
    embeds: embeds ?? this.embeds,
    reply: reply,
    reactions: reactions ?? this.reactions,
    isEdited: isEdited ?? this.isEdited,
    isPinned: isPinned ?? this.isPinned,
    mentionsCurrentMember: mentionsCurrentMember ?? this.mentionsCurrentMember,
  );
}
