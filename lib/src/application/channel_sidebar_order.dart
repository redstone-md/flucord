import 'package:collection/collection.dart';

import '../domain/chat_models.dart';
import '../domain/read_state.dart';

/// The channels the sidebar lists, in the order it lists them.
///
/// The sidebar draws these rows and the keyboard walks them, so a shortcut
/// lands on the row the reader expects to be next.
final class ChannelSidebarOrder {
  ChannelSidebarOrder({
    required CommunitySpace space,
    required List<ConversationChannel> channels,
    required List<ChannelCategory> categories,
    required Set<String> collapsedCategoryIds,
    required String? selectedChannelId,
    required ReadStateSnapshot readState,
    required ConversationChannel? Function(String id) channelOf,
  }) : _space = space,
       _channels = channels,
       categories = [...categories]
         ..sort((left, right) => left.position.compareTo(right.position)),
       _collapsedCategoryIds = collapsedCategoryIds,
       _selectedChannelId = selectedChannelId,
       _readState = readState,
       _channelOf = channelOf;

  final CommunitySpace _space;
  final List<ConversationChannel> _channels;
  final Set<String> _collapsedCategoryIds;
  final String? _selectedChannelId;
  final ReadStateSnapshot _readState;
  final ConversationChannel? Function(String id) _channelOf;

  /// The categories, top to bottom.
  final List<ChannelCategory> categories;

  late final List<ConversationChannel> _regular = _channels
      .where((channel) => !channel.isThread)
      .toList(growable: false);

  /// The active threads, without forum posts, which live in their forum.
  late final List<ConversationChannel> threads = _ordered(
    _channels.where(
      (channel) =>
          channel.isThread && !channel.isArchived && !_isForumPost(channel),
    ),
  );

  /// The direct messages, without the requests, which live in their folder.
  ///
  /// This is the one place the DM list is ordered: the latest activity first.
  /// A new message, a sent one or a new conversation moves a row here, on the
  /// next build. The sort is stable, so ids that tie keep the order given.
  late final List<ConversationChannel> conversations = () {
    final rows = _regular
        .where((channel) => !channel.isMessageRequest)
        .toList(growable: false);
    mergeSort(rows, compare: ConversationChannel.latestActivityFirst);
    return rows;
  }();

  /// The direct messages nobody has answered yet.
  late final List<ConversationChannel> messageRequests = _regular
      .where((channel) => channel.isMessageRequest)
      .toList(growable: false);

  /// The channels outside any category that exists here.
  late final List<ConversationChannel> uncategorized = () {
    final categoryIds = {for (final category in categories) category.id};
    return _ordered(
      _regular.where(
        (channel) =>
            channel.parentId == null || !categoryIds.contains(channel.parentId),
      ),
    );
  }();

  /// The channels of [kinds], for a server that has no categories at all.
  List<ConversationChannel> ofKinds(Set<ChannelKind> kinds) =>
      _ordered(_regular.where((channel) => kinds.contains(channel.kind)));

  /// Whether [category] has a channel this account can see, collapsed or not.
  bool hasChannelsIn(ChannelCategory category) =>
      _regular.any((channel) => channel.parentId == category.id);

  /// The rows [category] shows. A collapsed one keeps the open channel and the
  /// channels with something unread.
  List<ConversationChannel> rowsIn(ChannelCategory category) {
    final collapsed = _collapsedCategoryIds.contains(category.id);
    return _ordered(
      _regular.where(
        (channel) =>
            channel.parentId == category.id &&
            (!collapsed ||
                channel.id == _selectedChannelId ||
                _readState.showsUnread(channel)),
      ),
    );
  }

  /// Every row from top to bottom.
  List<ConversationChannel> get rows {
    if (_space.isDirectMessages) return conversations;
    if (categories.isEmpty) {
      return [
        ...ofKinds(const {ChannelKind.text}),
        ...threads,
        ...ofKinds(const {ChannelKind.forum, ChannelKind.media}),
        ...ofKinds(const {ChannelKind.voice}),
      ];
    }
    return [
      ...uncategorized,
      for (final category in categories) ...rowsIn(category),
      ...threads,
    ];
  }

  bool _isForumPost(ConversationChannel channel) {
    final parentId = channel.parentId;
    if (parentId == null) return false;
    final parent = _channelOf(parentId);
    return parent?.kind == ChannelKind.forum ||
        parent?.kind == ChannelKind.media;
  }

  List<ConversationChannel> _ordered(Iterable<ConversationChannel> source) =>
      _withoutHiddenMuted(
        source.toList(growable: false)..sort((left, right) {
          final position = left.position.compareTo(right.position);
          return position == 0 ? left.name.compareTo(right.name) : position;
        }),
      );

  /// R04's `hide_muted_channels`: a muted channel is dropped from the list
  /// unless it is the one on screen or it is shouting at the account anyway.
  List<ConversationChannel> _withoutHiddenMuted(
    List<ConversationChannel> source,
  ) {
    if (!_readState.settingsFor(_space.id).hideMutedChannels) return source;
    return [
      for (final channel in source)
        if (channel.id == _selectedChannelId ||
            channel.mentionCount > 0 ||
            !_readState.isChannelMuted(channel))
          channel,
    ];
  }
}
