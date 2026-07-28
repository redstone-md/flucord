import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../domain/read_state.dart';
import '../../domain/voice_connection.dart';
import '../../application/connection_controller.dart';
import '../../theme/flucord_theme.dart';
import 'account_panel.dart';
import 'guild_events_sidebar_button.dart';
import 'member_avatar.dart';
import 'notification_settings_menu.dart';

part 'channel_sidebar_rows.dart';

/// What a notification menu row wants doing, and to which channel.
///
/// A null channel means the space itself, which is what lets one callback
/// serve both the header menu and every row's context menu.
typedef SidebarNotificationHandler =
    void Function(
      NotificationMenuRequest request,
      ConversationChannel? channel,
    );

class ChannelSidebar extends StatelessWidget {
  const ChannelSidebar({
    required this.space,
    required this.channels,
    required this.selectedChannelId,
    required this.onSelectChannel,
    required this.sessionMode,
    required this.connectionStatus,
    required this.workspace,
    required this.collapsedCategoryIds,
    required this.onToggleCategory,
    required this.onNewDirectMessage,
    this.readState,
    this.onNotificationRequest,
    this.scheduledEventCount = 0,
    this.isLoadingScheduledEvents = false,
    this.scheduledEventsError,
    this.onOpenEvents,
    this.onOpenServerSettings,
    this.seatedByChannel = const {},
    super.key,
  });

  /// Who is sitting in each voice channel right now, keyed by channel id.
  ///
  /// Discord shows a voice channel's occupants under its row without anyone
  /// joining, and that is how a user decides which room to walk into. Reading
  /// it here rather than from the voice connection is what lets the sidebar
  /// answer for channels this client has never joined.
  final Map<String, List<VoiceParticipantStateEvent>> seatedByChannel;

  final CommunitySpace space;
  final List<ConversationChannel> channels;
  final String? selectedChannelId;
  final ValueChanged<String> onSelectChannel;
  final SessionMode sessionMode;
  final RepositoryConnectionStatus connectionStatus;
  final ChatWorkspace workspace;
  final Set<String> collapsedCategoryIds;
  final ValueChanged<String> onToggleCategory;
  final VoidCallback onNewDirectMessage;

  /// The server's read state, or null on a transport that has none.
  ///
  /// Mute, the resolved notification level and the unread-badge rule all come
  /// from here; without it the sidebar falls back to the channel's own unread
  /// flags, which is exactly the pre-server behaviour.
  final ReadStateSnapshot? readState;
  final SidebarNotificationHandler? onNotificationRequest;
  final int scheduledEventCount;
  final bool isLoadingScheduledEvents;
  final Object? scheduledEventsError;
  final VoidCallback? onOpenEvents;

  /// Opens the server-settings window. Null when the account may administer
  /// nothing here, or when the transport has no admin plane at all — the header
  /// then simply has no gear, which is what Discord does too.
  final VoidCallback? onOpenServerSettings;

  @override
  Widget build(BuildContext context) {
    final isDirect = space.isDirectMessages;
    final regularChannels = channels
        .where((channel) => !channel.isThread)
        .toList(growable: false);
    final threads = channels
        .where(
          (channel) =>
              channel.isThread && !channel.isArchived && !_isForumPost(channel),
        )
        .toList(growable: false);
    return Container(
      key: const ValueKey('channel-sidebar'),
      width: 236,
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border(right: BorderSide(color: context.surfaces.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.surfaces.border),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    space.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _spaceMuted
                          ? context.surfaces.muted
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (_spaceMuted)
                  Padding(
                    key: const ValueKey('space-muted'),
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      size: 15,
                      color: context.surfaces.muted,
                    ),
                  ),
                if (isDirect)
                  IconButton(
                    key: const ValueKey('new-direct-message'),
                    onPressed: onNewDirectMessage,
                    icon: const Icon(Icons.edit_square),
                    tooltip: 'New message',
                  ),
                if (!isDirect && onOpenServerSettings != null)
                  IconButton(
                    key: const ValueKey('open-server-settings'),
                    onPressed: onOpenServerSettings,
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    tooltip: 'Server settings',
                  ),
                if (onNotificationRequest != null)
                  PopupMenuButton<NotificationMenuRequest>(
                    key: const ValueKey('space-notification-menu'),
                    tooltip: 'Notification settings',
                    icon: const Icon(Icons.more_vert, size: 18),
                    padding: EdgeInsets.zero,
                    onSelected: (request) =>
                        onNotificationRequest!(request, null),
                    itemBuilder: (context) => notificationMenuItems(
                      muted: _spaceMuted,
                      level: _spaceSettings.messageNotifications,
                      isSpaceScope: true,
                      suppressEveryone: _spaceSettings.suppressEveryone,
                      mobilePush: _spaceSettings.mobilePush,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
              children: _navigationEntries(
                isDirect: isDirect,
                regularChannels: regularChannels,
                threads: threads,
              ),
            ),
          ),
          AccountPanel(
            member: workspace.memberById(workspace.currentMemberId),
            sessionMode: sessionMode,
            connectionStatus: connectionStatus,
          ),
        ],
      ),
    );
  }

  ReadStateSnapshot get _readState => readState ?? ReadStateSnapshot.empty;

  GuildNotificationSettings get _spaceSettings =>
      _readState.settingsFor(space.id);

  bool get _spaceMuted => _readState.isSpaceMuted(space.id);

  bool _isMuted(ConversationChannel channel) =>
      _readState.isChannelMuted(channel);

  /// Whether the row should read as unread.
  ///
  /// A mention always shows. Otherwise R04's resolved unread badge decides: a
  /// channel set to "only mentions" stays quiet in the sidebar even though the
  /// server does consider it unread.
  bool _showsUnread(ConversationChannel channel) {
    if (channel.mentionCount > 0) return true;
    if (!channel.unread) return false;
    return _readState.unreadBadgeFor(channel) == UnreadBadge.allMessages;
  }

  /// R04's `hide_muted_channels`: a muted channel is dropped from the list
  /// unless it is the one on screen or it is shouting at the account anyway.
  List<ConversationChannel> _withoutHiddenMuted(
    List<ConversationChannel> source,
  ) {
    if (!_spaceSettings.hideMutedChannels) return source;
    return [
      for (final channel in source)
        if (channel.id == selectedChannelId ||
            channel.mentionCount > 0 ||
            !_isMuted(channel))
          channel,
    ];
  }

  bool _isForumPost(ConversationChannel channel) {
    final parentId = channel.parentId;
    if (parentId == null) return false;
    final parent = workspace.channelOrNull(parentId);
    return parent?.kind == ChannelKind.forum ||
        parent?.kind == ChannelKind.media;
  }

  List<Widget> _navigationEntries({
    required bool isDirect,
    required List<ConversationChannel> regularChannels,
    required List<ConversationChannel> threads,
  }) {
    if (isDirect) {
      return [
        const _SectionLabel(label: 'Messages'),
        for (final channel in regularChannels) _rowFor(channel),
      ];
    }
    final categories = [...workspace.categoriesFor(space.id)]
      ..sort((left, right) => left.position.compareTo(right.position));
    if (categories.isEmpty) {
      return [
        ..._eventEntries(),
        ..._uncategorizedEntries(regularChannels, threads),
      ];
    }
    final categoryIds = categories.map((category) => category.id).toSet();
    final uncategorized = _ordered(
      regularChannels.where(
        (channel) =>
            channel.parentId == null || !categoryIds.contains(channel.parentId),
      ),
    );
    return [
      ..._eventEntries(),
      if (uncategorized.isNotEmpty) ...[
        const _SectionLabel(label: 'Channels'),
        for (final channel in uncategorized) _rowFor(channel),
        const SizedBox(height: 10),
      ],
      for (final category in categories)
        // A category whose every channel was filtered out is dropped whole.
        // Collapsing hides rows without emptying this list, so a collapsed
        // category still keeps its header — only a category the account
        // cannot see into loses one.
        if (regularChannels.any((channel) => channel.parentId == category.id))
          _CategorySection(
            category: category,
            collapsed: collapsedCategoryIds.contains(category.id),
            onToggle: () => onToggleCategory(category.id),
            children: [
              for (final channel in _visibleCategoryChannels(
                category,
                regularChannels,
              ))
                _rowFor(channel),
            ],
          ),
      if (threads.isNotEmpty) ...[
        const SizedBox(height: 10),
        const _SectionLabel(label: 'Active threads'),
        for (final channel in _ordered(threads))
          _rowFor(channel, indented: true),
      ],
    ];
  }

  List<Widget> _eventEntries() {
    if (scheduledEventCount == 0 &&
        !isLoadingScheduledEvents &&
        scheduledEventsError == null) {
      return const [];
    }
    return [
      GuildEventsSidebarButton(
        count: scheduledEventCount,
        isLoading: isLoadingScheduledEvents,
        hasError: scheduledEventsError != null,
        onPressed: onOpenEvents ?? () {},
      ),
      const SizedBox(height: 10),
    ];
  }

  List<Widget> _uncategorizedEntries(
    List<ConversationChannel> channels,
    List<ConversationChannel> threads,
  ) {
    final text = _ordered(
      channels.where((channel) => channel.kind == ChannelKind.text),
    );
    final voice = _ordered(
      channels.where((channel) => channel.kind == ChannelKind.voice),
    );
    final forums = _ordered(
      channels.where(
        (channel) =>
            channel.kind == ChannelKind.forum ||
            channel.kind == ChannelKind.media,
      ),
    );
    return [
      if (text.isNotEmpty) ...[
        const _SectionLabel(label: 'Text channels'),
        for (final channel in text) _rowFor(channel),
      ],
      if (threads.isNotEmpty) ...[
        const SizedBox(height: 18),
        const _SectionLabel(label: 'Active threads'),
        for (final channel in _ordered(threads))
          _rowFor(channel, indented: true),
      ],
      if (forums.isNotEmpty) ...[
        const SizedBox(height: 18),
        const _SectionLabel(label: 'Forums'),
        for (final channel in forums) _rowFor(channel),
      ],
      if (voice.isNotEmpty) ...[
        const SizedBox(height: 18),
        const _SectionLabel(label: 'Voice channels'),
        for (final channel in voice) ..._voiceEntry(channel),
      ],
    ];
  }

  List<ConversationChannel> _visibleCategoryChannels(
    ChannelCategory category,
    List<ConversationChannel> channels,
  ) {
    final collapsed = collapsedCategoryIds.contains(category.id);
    return _ordered(
      channels.where(
        (channel) =>
            channel.parentId == category.id &&
            (!collapsed ||
                channel.id == selectedChannelId ||
                _showsUnread(channel)),
      ),
    );
  }

  List<ConversationChannel> _ordered(Iterable<ConversationChannel> source) =>
      _withoutHiddenMuted(
        source.toList(growable: false)..sort((left, right) {
          final position = left.position.compareTo(right.position);
          return position == 0 ? left.name.compareTo(right.name) : position;
        }),
      );

  /// A voice channel row followed by whoever is seated in it.
  List<Widget> _voiceEntry(
    ConversationChannel channel, {
    bool indented = false,
  }) => [
    _rowFor(channel, indented: indented),
    for (final seat in seatedByChannel[channel.id] ?? const [])
      VoiceSeatRow(
        key: ValueKey('voice-seat-${channel.id}-${seat.userId}'),
        state: seat,
        member: workspace.memberOrNull(seat.userId),
        spaceId: space.id,
        indented: indented,
      ),
  ];

  _ChannelRow _rowFor(ConversationChannel channel, {bool indented = false}) =>
      _ChannelRow(
        channel: channel,
        selected: channel.id == selectedChannelId,
        recipient: channel.recipientId == null
            ? null
            : workspace.memberOrNull(channel.recipientId!),
        indented: indented,
        muted: _isMuted(channel),
        showsUnread: _showsUnread(channel),
        notificationLevel: _readState.notificationLevelFor(channel),
        onNotificationRequest: onNotificationRequest == null
            ? null
            : (request) => onNotificationRequest!(request, channel),
        onPressed: () => onSelectChannel(channel.id),
      );
}
