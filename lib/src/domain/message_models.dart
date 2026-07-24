part of 'chat_models.dart';

enum DiscordMessageType {
  defaultMessage(0),
  recipientAdd(1),
  recipientRemove(2),
  call(3),
  channelNameChange(4),
  channelIconChange(5),
  channelPinnedMessage(6),
  userJoin(7),
  guildBoost(8),
  guildBoostTier1(9),
  guildBoostTier2(10),
  guildBoostTier3(11),
  channelFollowAdd(12),
  guildDiscoveryDisqualified(14),
  guildDiscoveryRequalified(15),
  guildDiscoveryGracePeriodInitialWarning(16),
  guildDiscoveryGracePeriodFinalWarning(17),
  threadCreated(18),
  reply(19),
  chatInputCommand(20),
  threadStarterMessage(21),
  guildInviteReminder(22),
  contextMenuCommand(23),
  autoModerationAction(24),
  roleSubscriptionPurchase(25),
  interactionPremiumUpsell(26),
  stageStart(27),
  stageEnd(28),
  stageSpeaker(29),
  stageTopic(31),
  guildApplicationPremiumSubscription(32),
  guildIncidentAlertModeEnabled(36),
  guildIncidentAlertModeDisabled(37),
  guildIncidentReportRaid(38),
  guildIncidentReportFalseAlarm(39),
  purchaseNotification(44),
  pollResult(46),
  unknown(-1);

  const DiscordMessageType(this.discordValue);

  final int discordValue;

  static DiscordMessageType fromDiscordValue(int? value) {
    for (final type in values) {
      if (type.discordValue == value) return type;
    }
    return unknown;
  }

  bool get isSystem => switch (this) {
    defaultMessage ||
    reply ||
    chatInputCommand ||
    threadStarterMessage ||
    contextMenuCommand ||
    autoModerationAction ||
    interactionPremiumUpsell ||
    purchaseNotification ||
    pollResult ||
    unknown => false,
    _ => true,
  };
}

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

final class MessageReference {
  const MessageReference({this.messageId, this.channelId});

  final String? messageId;
  final String? channelId;
}

final class MessageReaction {
  const MessageReaction({
    required this.emojiName,
    required this.count,
    this.emojiId,
    this.animated = false,
    this.reactedByCurrentUser = false,
    int? normalCount,
    this.burstCount = 0,
    this.burstByCurrentUser = false,
    this.burstColorValues = const [],
  }) : normalCount = normalCount ?? count;

  final String emojiName;
  final String? emojiId;
  final int count;
  final bool animated;
  final int normalCount;
  final int burstCount;
  final bool reactedByCurrentUser;
  final bool burstByCurrentUser;
  final List<int> burstColorValues;

  String get key => emojiId == null ? emojiName : '$emojiName:$emojiId';

  MessageReaction copyWith({
    int? count,
    int? normalCount,
    int? burstCount,
    bool? reactedByCurrentUser,
    bool? burstByCurrentUser,
    List<int>? burstColorValues,
  }) => MessageReaction(
    emojiName: emojiName,
    emojiId: emojiId,
    count: count ?? this.count,
    animated: animated,
    normalCount: normalCount ?? this.normalCount,
    burstCount: burstCount ?? this.burstCount,
    reactedByCurrentUser: reactedByCurrentUser ?? this.reactedByCurrentUser,
    burstByCurrentUser: burstByCurrentUser ?? this.burstByCurrentUser,
    burstColorValues: burstColorValues ?? this.burstColorValues,
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
    List<MessageSticker> stickers = const [],
    this.poll,
    this.reply,
    this.reference,
    this.type = DiscordMessageType.defaultMessage,
    this.isEdited = false,
    this.isPinned = false,
    this.mentionsCurrentMember = false,
  }) : attachments = List.unmodifiable(attachments),
       embeds = List.unmodifiable(embeds),
       reactions = List.unmodifiable(reactions),
       stickers = List.unmodifiable(stickers);

  final String id;
  final String channelId;
  final String authorId;
  final String body;
  final DateTime sentAt;
  final List<MessageAttachment> attachments;
  final List<MessageEmbed> embeds;
  final List<MessageSticker> stickers;
  final MessagePoll? poll;
  final MessageReply? reply;
  final MessageReference? reference;
  final DiscordMessageType type;
  final List<MessageReaction> reactions;
  final bool isEdited;
  final bool isPinned;
  final bool mentionsCurrentMember;

  bool get isSystem => type.isSystem;

  ChatMessage copyWith({
    String? body,
    List<MessageAttachment>? attachments,
    List<MessageEmbed>? embeds,
    List<MessageReaction>? reactions,
    List<MessageSticker>? stickers,
    MessagePoll? poll,
    MessageReference? reference,
    DiscordMessageType? type,
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
    stickers: stickers ?? this.stickers,
    poll: poll ?? this.poll,
    reply: reply,
    reference: reference ?? this.reference,
    type: type ?? this.type,
    reactions: reactions ?? this.reactions,
    isEdited: isEdited ?? this.isEdited,
    isPinned: isPinned ?? this.isPinned,
    mentionsCurrentMember: mentionsCurrentMember ?? this.mentionsCurrentMember,
  );
}
