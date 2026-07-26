import 'chat_models.dart';
import 'discord_permissions.dart';

/// What the signed-in account may do in one channel, as plain answers.
///
/// The bitfield is the truth, but a widget asking "do I draw the pin button"
/// should not be doing bit arithmetic — every call site that did would be a
/// place to get the mask wrong. This is the whole permission surface Flucord
/// currently offers a control for, resolved once per channel.
final class ChannelCapabilities {
  const ChannelCapabilities({
    required this.viewChannel,
    required this.sendMessages,
    required this.manageMessages,
    required this.pinMessages,
    required this.createPublicThreads,
    required this.addReactions,
    required this.attachFiles,
    required this.embedLinks,
  });

  /// Everything allowed. Used where no permission data exists at all — a demo
  /// workspace, a transport that never carried roles — because withholding
  /// actions on missing data would break surfaces that work today, while
  /// offering one the server rejects is exactly the behaviour being replaced.
  static const unrestricted = ChannelCapabilities(
    viewChannel: true,
    sendMessages: true,
    manageMessages: true,
    pinMessages: true,
    createPublicThreads: true,
    addReactions: true,
    attachFiles: true,
    embedLinks: true,
  );

  /// Nothing allowed, for a channel that resolved to no permissions at all.
  static const none = ChannelCapabilities(
    viewChannel: false,
    sendMessages: false,
    manageMessages: false,
    pinMessages: false,
    createPublicThreads: false,
    addReactions: false,
    attachFiles: false,
    embedLinks: false,
  );

  /// Reads the answers out of a computed permission bitfield.
  factory ChannelCapabilities.fromPermissions(BigInt permissions) =>
      ChannelCapabilities(
        viewChannel: DiscordPermissions.hasAll(
          permissions,
          DiscordPermissions.viewChannel,
        ),
        sendMessages: DiscordPermissions.hasAll(
          permissions,
          DiscordPermissions.sendMessages,
        ),
        manageMessages: DiscordPermissions.hasAll(
          permissions,
          DiscordPermissions.manageMessages,
        ),
        pinMessages: DiscordPermissions.hasAll(
          permissions,
          DiscordPermissions.pinMessages,
        ),
        createPublicThreads: DiscordPermissions.hasAll(
          permissions,
          DiscordPermissions.createPublicThreads,
        ),
        addReactions: DiscordPermissions.hasAll(
          permissions,
          DiscordPermissions.addReactions,
        ),
        attachFiles: DiscordPermissions.hasAll(
          permissions,
          DiscordPermissions.attachFiles,
        ),
        embedLinks: DiscordPermissions.hasAll(
          permissions,
          DiscordPermissions.embedLinks,
        ),
      );

  final bool viewChannel;
  final bool sendMessages;

  /// Deleting or otherwise moderating a message that is not your own.
  final bool manageMessages;
  final bool pinMessages;
  final bool createPublicThreads;
  final bool addReactions;
  final bool attachFiles;
  final bool embedLinks;

  /// Whether [message] may be acted on as its owner would: your own always,
  /// anyone else's only with `MANAGE_MESSAGES`. This is the rule behind both
  /// deleting a message and suppressing its embeds.
  bool canModerate(ChatMessage message, {required String currentMemberId}) =>
      message.authorId == currentMemberId || manageMessages;

  @override
  bool operator ==(Object other) =>
      other is ChannelCapabilities &&
      other.viewChannel == viewChannel &&
      other.sendMessages == sendMessages &&
      other.manageMessages == manageMessages &&
      other.pinMessages == pinMessages &&
      other.createPublicThreads == createPublicThreads &&
      other.addReactions == addReactions &&
      other.attachFiles == attachFiles &&
      other.embedLinks == embedLinks;

  @override
  int get hashCode => Object.hash(
    viewChannel,
    sendMessages,
    manageMessages,
    pinMessages,
    createPublicThreads,
    addReactions,
    attachFiles,
    embedLinks,
  );
}
