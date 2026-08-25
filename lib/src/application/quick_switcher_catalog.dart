import '../domain/chat_models.dart';
import '../domain/workspace_activity.dart';

enum QuickSwitcherDestinationKind {
  guild,
  directMessage,
  textChannel,
  voiceChannel,
  forumChannel,
  mediaChannel,
  thread,
}

final class QuickSwitcherDestination {
  const QuickSwitcherDestination({
    required this.kind,
    required this.spaceId,
    required this.title,
    required this.path,
    required this.unread,
    required this.mentionCount,
    this.channelId,
  });

  final QuickSwitcherDestinationKind kind;
  final String spaceId;
  final String? channelId;
  final String title;
  final String path;
  final bool unread;
  final int mentionCount;

  String get key => '${kind.name}:${channelId ?? spaceId}';
}

/// The last catalogue built for a workspace, so a rebuild can reuse it.
final _quickSwitcherByWorkspace = Expando<QuickSwitcherCatalog>();

final class QuickSwitcherCatalog {
  QuickSwitcherCatalog._(List<QuickSwitcherDestination> destinations)
    : _destinations = List.unmodifiable(destinations);

  /// Builds every destination in [workspace], reusing the last catalogue built
  /// for it. A workspace never changes once created, so the previous catalogue
  /// stays correct until a new workspace replaces it.
  factory QuickSwitcherCatalog.fromWorkspace(ChatWorkspace workspace) =>
      _quickSwitcherByWorkspace[workspace] ??= _build(workspace);

  static QuickSwitcherCatalog _build(ChatWorkspace workspace) {
    final activity = workspace.activityBySpace();
    final guilds = workspace.spaces
        .where((space) => !space.isDirectMessages)
        .map((space) {
          final spaceActivity = activity[space.id] ?? SpaceActivity.none;
          return QuickSwitcherDestination(
            kind: QuickSwitcherDestinationKind.guild,
            spaceId: space.id,
            title: space.name,
            path: space.name,
            unread: spaceActivity.hasUnread,
            mentionCount: spaceActivity.mentionCount,
          );
        });

    final channels = workspace.channels
        .where((channel) => !channel.isArchived)
        .map((channel) => _channelDestination(workspace, channel));
    final groupedChannels = <QuickSwitcherDestination>[];
    for (final kind in const [
      QuickSwitcherDestinationKind.directMessage,
      QuickSwitcherDestinationKind.textChannel,
      QuickSwitcherDestinationKind.voiceChannel,
      QuickSwitcherDestinationKind.forumChannel,
      QuickSwitcherDestinationKind.mediaChannel,
      QuickSwitcherDestinationKind.thread,
    ]) {
      groupedChannels.addAll(
        channels.where((destination) => destination.kind == kind),
      );
    }
    return QuickSwitcherCatalog._([...guilds, ...groupedChannels]);
  }

  final List<QuickSwitcherDestination> _destinations;

  List<QuickSwitcherDestination> get destinations => _destinations;

  List<QuickSwitcherDestination> search(String query) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) return _destinations;
    return _destinations
        .where((destination) {
          final candidate = '${destination.title} ${destination.path}'
              .toLowerCase();
          return terms.every(candidate.contains);
        })
        .toList(growable: false);
  }

  static QuickSwitcherDestination _channelDestination(
    ChatWorkspace workspace,
    ConversationChannel channel,
  ) {
    final space = workspace.spaceById(channel.spaceId);
    final isDirect = channel.isDirectMessage || space.isDirectMessages;
    final kind = isDirect
        ? QuickSwitcherDestinationKind.directMessage
        : channel.isThread
        ? QuickSwitcherDestinationKind.thread
        : channel.kind == ChannelKind.forum
        ? QuickSwitcherDestinationKind.forumChannel
        : channel.kind == ChannelKind.media
        ? QuickSwitcherDestinationKind.mediaChannel
        : channel.kind == ChannelKind.voice
        ? QuickSwitcherDestinationKind.voiceChannel
        : QuickSwitcherDestinationKind.textChannel;
    final title = switch (kind) {
      QuickSwitcherDestinationKind.directMessage =>
        '@${_recipientName(workspace, channel)}',
      QuickSwitcherDestinationKind.voiceChannel => channel.name,
      QuickSwitcherDestinationKind.forumChannel ||
      QuickSwitcherDestinationKind.mediaChannel => channel.name,
      QuickSwitcherDestinationKind.textChannel ||
      QuickSwitcherDestinationKind.thread => '#${channel.name}',
      QuickSwitcherDestinationKind.guild => space.name,
    };
    return QuickSwitcherDestination(
      kind: kind,
      spaceId: space.id,
      channelId: channel.id,
      title: title,
      path: '${space.name} / $title',
      unread: channel.unread || channel.mentionCount > 0,
      mentionCount: channel.mentionCount,
    );
  }

  static String _recipientName(
    ChatWorkspace workspace,
    ConversationChannel channel,
  ) {
    final recipientId = channel.recipientId;
    if (recipientId == null) return channel.name;
    return workspace.memberOrNull(recipientId)?.displayName ?? channel.name;
  }
}
