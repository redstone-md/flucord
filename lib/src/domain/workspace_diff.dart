part of 'chat_models.dart';

/// What a READY changes in the account's servers, categories and channels.
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

  bool get isEmpty =>
      removedSpaceIds.isEmpty &&
      removedCategoryIds.isEmpty &&
      removedChannelIds.isEmpty &&
      spaces.isEmpty &&
      categories.isEmpty &&
      channels.isEmpty &&
      members.isEmpty;

  /// Whether [channel] goes, by itself or with its server.
  bool removes(ConversationChannel channel) =>
      removedChannelIds.contains(channel.id) ||
      removedSpaceIds.contains(channel.spaceId);
}
