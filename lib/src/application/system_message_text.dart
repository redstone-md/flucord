import '../domain/chat_models.dart';

abstract final class SystemMessageText {
  static String describe(ChatMessage message, String authorName) {
    final detail = message.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return switch (message.type) {
      DiscordMessageType.recipientAdd => '$authorName joined the thread.',
      DiscordMessageType.recipientRemove => '$authorName left the thread.',
      DiscordMessageType.call => '$authorName started a call.',
      DiscordMessageType.channelNameChange =>
        detail.isEmpty
            ? '$authorName changed the channel name.'
            : '$authorName changed the channel name: $detail',
      DiscordMessageType.channelIconChange =>
        '$authorName changed the channel icon.',
      DiscordMessageType.channelPinnedMessage =>
        '$authorName pinned a message to this channel.',
      DiscordMessageType.userJoin => '$authorName joined the server.',
      DiscordMessageType.guildBoost => '$authorName boosted the server.',
      DiscordMessageType.guildBoostTier1 =>
        '$authorName boosted the server to Level 1.',
      DiscordMessageType.guildBoostTier2 =>
        '$authorName boosted the server to Level 2.',
      DiscordMessageType.guildBoostTier3 =>
        '$authorName boosted the server to Level 3.',
      DiscordMessageType.channelFollowAdd =>
        '$authorName added this channel to another server.',
      DiscordMessageType.guildDiscoveryDisqualified =>
        'This server was removed from Server Discovery.',
      DiscordMessageType.guildDiscoveryRequalified =>
        'This server is eligible for Server Discovery again.',
      DiscordMessageType.guildDiscoveryGracePeriodInitialWarning ||
      DiscordMessageType.guildDiscoveryGracePeriodFinalWarning =>
        'This server is at risk of leaving Server Discovery.',
      DiscordMessageType.threadCreated =>
        detail.isEmpty
            ? '$authorName started a thread.'
            : '$authorName started a thread: $detail',
      DiscordMessageType.guildInviteReminder =>
        'Invite friends to help this server grow.',
      DiscordMessageType.roleSubscriptionPurchase =>
        '$authorName purchased a premium server subscription.',
      DiscordMessageType.stageStart =>
        detail.isEmpty
            ? '$authorName started a Stage.'
            : '$authorName started a Stage: $detail',
      DiscordMessageType.stageEnd => '$authorName ended the Stage.',
      DiscordMessageType.stageSpeaker => '$authorName is now a Stage speaker.',
      DiscordMessageType.stageTopic =>
        detail.isEmpty
            ? '$authorName changed the Stage topic.'
            : '$authorName changed the Stage topic: $detail',
      DiscordMessageType.guildApplicationPremiumSubscription =>
        '$authorName upgraded an application in this server.',
      DiscordMessageType.guildIncidentAlertModeEnabled =>
        'Security actions were enabled for this server.',
      DiscordMessageType.guildIncidentAlertModeDisabled =>
        'Security actions were disabled for this server.',
      DiscordMessageType.guildIncidentReportRaid =>
        'A raid was reported in this server.',
      DiscordMessageType.guildIncidentReportFalseAlarm =>
        'The reported raid was marked as a false alarm.',
      _ => 'Server event',
    };
  }
}
