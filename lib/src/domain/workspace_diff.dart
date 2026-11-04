part of 'chat_models.dart';

/// What a READY changes in the account's servers, categories, channels, roles,
/// emoji and stickers, and in the account's own standing in each server.
///
/// A reconnect that could not resume can change thousands of channels. They
/// travel together, so the screen redraws once and the cache commits once.
final class WorkspaceDiff {
  const WorkspaceDiff({
    this.removedSpaceIds = const {},
    this.removedCategoryIds = const {},
    this.removedChannelIds = const {},
    this.spaces = const [],
    this.categories = const [],
    this.channels = const [],
    this.members = const [],
    this.removedRoleIds = const {},
    this.roles = const [],
    this.ownMemberships = const {},
    this.emojisBySpace = const {},
    this.stickersBySpace = const {},
  });

  final Set<String> removedSpaceIds;
  final Set<String> removedCategoryIds;
  final Set<String> removedChannelIds;

  /// Servers that are new or changed. The same goes for [categories] and
  /// [channels].
  final List<CommunitySpace> spaces;
  final List<ChannelCategory> categories;
  final List<ConversationChannel> channels;

  /// The recipients of new direct messages.
  final List<Member> members;

  /// Roles that are gone, apart from those that go with their server.
  final Set<String> removedRoleIds;

  /// Roles that are new or changed.
  final List<CommunityRole> roles;

  /// The account's own standing in each server where it is new or changed,
  /// keyed by server. Permissions start from it.
  final Map<String, GuildMembership> ownMemberships;

  /// Each server whose emoji changed, with all of its emoji now. The same goes
  /// for [stickersBySpace].
  final Map<String, List<GuildEmoji>> emojisBySpace;
  final Map<String, List<GuildSticker>> stickersBySpace;

  bool get isEmpty =>
      removedSpaceIds.isEmpty &&
      removedCategoryIds.isEmpty &&
      removedChannelIds.isEmpty &&
      spaces.isEmpty &&
      categories.isEmpty &&
      channels.isEmpty &&
      members.isEmpty &&
      removedRoleIds.isEmpty &&
      roles.isEmpty &&
      ownMemberships.isEmpty &&
      emojisBySpace.isEmpty &&
      stickersBySpace.isEmpty;

  /// Whether [channel] goes, by itself or with its server.
  bool removes(ConversationChannel channel) =>
      removedChannelIds.contains(channel.id) ||
      removedSpaceIds.contains(channel.spaceId);
}
