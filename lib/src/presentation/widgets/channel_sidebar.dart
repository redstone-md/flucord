import 'package:flutter/material.dart';

import '../../application/connection_controller.dart';
import '../../application/friends_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../domain/flucord_palette.dart';
import '../../domain/read_state.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_theme.dart';
import 'account_panel.dart';
import 'friends_panel.dart';
import 'guild_events_sidebar_button.dart';
import 'member_avatar.dart';
import 'mention_badge.dart';
import 'notification_settings_menu.dart';
import 'theme_scope.dart';
import 'user_settings_scope.dart';

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
    this.onOpenMemberProfile,
    required this.sessionMode,
    required this.connectionStatus,
    required this.categories,
    required this.currentMember,
    required this.memberOf,
    required this.channelOf,
    required this.collapsedCategoryIds,
    required this.onToggleCategory,
    required this.onNewDirectMessage,
    this.onAcceptMessageRequest,
    this.onDeclineMessageRequest,
    this.readState,
    this.onNotificationRequest,
    this.scheduledEventCount = 0,
    this.isLoadingScheduledEvents = false,
    this.scheduledEventsError,
    this.onOpenEvents,
    this.onOpenServerSettings,
    this.onLeaveServer,
    this.onReportServer,
    this.friends,
    this.seatedByChannel = const {},
    this.voiceConnectionBar,
    super.key,
  });

  /// Who is sitting in each voice channel right now, keyed by channel id.
  ///
  /// Discord shows a voice channel's occupants under its row without anyone
  /// joining, and that is how a user decides which room to walk into. Reading
  /// it here rather than from the voice connection is what lets the sidebar
  /// answer for channels this client has never joined.
  final Map<String, List<VoiceParticipantStateEvent>> seatedByChannel;

  /// The strip that keeps a live voice connection reachable, or null when
  /// there is none. Passed in rather than built here so the sidebar does not
  /// have to know about the voice controller.
  final Widget? voiceConnectionBar;

  final CommunitySpace space;
  final List<ConversationChannel> channels;
  final String? selectedChannelId;
  final ValueChanged<String> onSelectChannel;

  /// Opens somebody sitting in a voice channel. Absent on a surface with
  /// nowhere to show a profile.
  final void Function(String userId)? onOpenMemberProfile;
  final SessionMode sessionMode;
  final RepositoryConnectionStatus connectionStatus;

  /// The space's categories, in whatever order they arrived.
  final List<ChannelCategory> categories;

  /// The account itself, for the panel at the bottom.
  final Member currentMember;

  /// Looks a member up when a row is drawn — a voice seat, the other side of a
  /// direct message, a friend's presence.
  ///
  /// Read through to whatever the workspace holds now rather than handed a
  /// copy: the sidebar can be kept across rebuilds, and a captured table would
  /// answer with whatever it held when it was built. The members a row does
  /// show are named in the sidebar's dependencies, so a change to one of them
  /// still redraws it.
  final Member? Function(String userId) memberOf;

  /// Looks a channel up while classifying a thread's parent. Read through for
  /// the same reason as [memberOf].
  final ConversationChannel? Function(String channelId) channelOf;

  final Set<String> collapsedCategoryIds;
  final ValueChanged<String> onToggleCategory;
  final VoidCallback onNewDirectMessage;

  /// Answers a message request in the folder, by channel id. Null on a
  /// surface that cannot answer one, which leaves the folder read-only.
  final void Function(String channelId)? onAcceptMessageRequest;
  final void Function(String channelId)? onDeclineMessageRequest;

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

  /// Leaves the server. Null on a transport that cannot leave anything and
  /// in the direct-messages space, which is nobody's server.
  final VoidCallback? onLeaveServer;

  /// Reports the server to Discord, or null on a transport with no report
  /// flow and in the direct-messages space, which is nobody's server.
  final VoidCallback? onReportServer;

  /// The friend graph, shown in place of the conversation list in direct
  /// messages. Null on a transport that is never told one.
  final FriendsController? friends;

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
    // The account's dark-sidebar answer, read here so the flag from any
    // device repaints the rail. It only applies to the built-in light
    // palette: an installed theme is never overridden, its author picked
    // the panel colours on purpose.
    final darkSidebar =
        UserSettingsScope.appearanceOf(context).drawsDarkSidebar &&
        Theme.of(context).brightness == Brightness.light &&
        ThemeScope.maybeOf(context) == null;
    final content = Container(
      key: const ValueKey('channel-sidebar'),
      width: 236,
      decoration: BoxDecoration(
        color: context.surfaces.rail,
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
                if (isDirect && friends != null)
                  IconButton(
                    key: const ValueKey('toggle-friends'),
                    onPressed: friends!.togglePanel,
                    icon: Icon(
                      friends!.isPanelOpen
                          ? Icons.forum_outlined
                          : Icons.people_alt_outlined,
                      size: 18,
                    ),
                    tooltip: friends!.isPanelOpen ? 'Conversations' : 'Friends',
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
                if (!isDirect && onLeaveServer != null)
                  IconButton(
                    key: const ValueKey('leave-server'),
                    onPressed: onLeaveServer,
                    icon: const Icon(Icons.logout_outlined, size: 18),
                    tooltip: 'Leave server',
                  ),
                if (!isDirect && onReportServer != null)
                  IconButton(
                    key: const ValueKey('report-server'),
                    onPressed: onReportServer,
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    tooltip: 'Report server',
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
            child: isDirect && (friends?.isPanelOpen ?? false)
                // The friend graph takes the whole pane rather than sitting
                // above the conversations: both are long lists, and stacking
                // them means neither can be read.
                ? FriendsPanel(
                    controller: friends!,
                    // From the workspace, which the presence service already
                    // keeps current; a second copy would be a second thing to
                    // go stale.
                    presenceOf: (userId) => memberOf(userId)?.presence,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
                    children: _navigationEntries(
                      isDirect: isDirect,
                      regularChannels: regularChannels,
                      threads: threads,
                    ),
                  ),
          ),
          ?voiceConnectionBar,
          AccountPanel(
            member: currentMember,
            sessionMode: sessionMode,
            connectionStatus: connectionStatus,
          ),
        ],
      ),
    );
    if (!darkSidebar) return content;
    // The whole rail repaints with the dark palette, so the rows keep a
    // readable foreground instead of light-theme text on a dark ground.
    return Theme(
      data: FlucordTheme.fromPalette(FlucordPalette.dark),
      child: content,
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
    final parent = channelOf(parentId);
    return parent?.kind == ChannelKind.forum ||
        parent?.kind == ChannelKind.media;
  }

  List<Widget> _navigationEntries({
    required bool isDirect,
    required List<ConversationChannel> regularChannels,
    required List<ConversationChannel> threads,
  }) {
    if (isDirect) return _directMessageEntries(regularChannels);
    final sortedCategories = [...categories]
      ..sort((left, right) => left.position.compareTo(right.position));
    if (sortedCategories.isEmpty) {
      return [
        ..._eventEntries(),
        ..._uncategorizedEntries(regularChannels, threads),
      ];
    }
    final categoryIds = sortedCategories.map((category) => category.id).toSet();
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
      for (final category in sortedCategories)
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
              // Voice channels carry their occupants here too. They only did
              // outside categories, which is where almost no server puts
              // them, so every seat was invisible in practice.
              for (final channel in _visibleCategoryChannels(
                category,
                regularChannels,
              ))
                if (channel.kind == ChannelKind.voice)
                  ..._voiceEntry(channel)
                else
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

  /// The direct-messages block: the conversations, with the unanswered
  /// requests folded into their folder.
  ///
  /// A request never sits in the main list. Discord hides it there until the
  /// account answers it, which is the whole point of the folder, so the split
  /// happens here rather than in whatever built the channel list.
  List<Widget> _directMessageEntries(List<ConversationChannel> channels) {
    final requests = channels
        .where((channel) => channel.isMessageRequest)
        .toList(growable: false);
    final conversations = channels
        .where((channel) => !channel.isMessageRequest)
        .toList(growable: false);
    return [
      _DirectMessagesFolder(
        requests: requests,
        conversationRows: [
          for (final channel in conversations) _rowFor(channel),
        ],
        requestRows: [for (final channel in requests) _requestRowFor(channel)],
      ),
    ];
  }

  _MessageRequestRow _requestRowFor(ConversationChannel channel) =>
      _MessageRequestRow(
        channel: channel,
        recipient: channel.recipientId == null
            ? null
            : memberOf(channel.recipientId!),
        onPressed: () => onSelectChannel(channel.id),
        onAccept: onAcceptMessageRequest == null
            ? null
            : () => onAcceptMessageRequest!(channel.id),
        onDecline: onDeclineMessageRequest == null
            ? null
            : () => onDeclineMessageRequest!(channel.id),
      );

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
        member: memberOf(seat.userId),
        spaceId: space.id,
        indented: indented,
        onOpenProfile: onOpenMemberProfile,
      ),
  ];

  _ChannelRow _rowFor(ConversationChannel channel, {bool indented = false}) =>
      _ChannelRow(
        channel: channel,
        selected: channel.id == selectedChannelId,
        recipient: channel.recipientId == null
            ? null
            : memberOf(channel.recipientId!),
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
