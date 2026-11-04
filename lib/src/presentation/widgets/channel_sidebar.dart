import 'package:flutter/material.dart';

import '../../application/channel_sidebar_order.dart';
import '../../application/connection_controller.dart';
import '../../application/friends_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../domain/read_state.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'server_menu.dart';
import 'account_panel.dart';
import 'activity_label.dart';
import 'activity_views.dart';
import 'friends_panel.dart';
import 'guild_events_sidebar_button.dart';
import 'member_avatar.dart';
import 'count_badge.dart';
import 'direct_message_views.dart';
import 'flucord_icon_button.dart';
import 'notification_settings_menu.dart';
import 'sidebar_row_metrics.dart';

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
    this.speakingUserIds = const {},
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

  /// Who is speaking right now, by user id. Only known for the room this
  /// client is in, so a seat elsewhere never shows the speaking ring.
  final Set<String> speakingUserIds;

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
  /// nothing here, or when the transport has no admin plane at all. The header
  /// menu then has no settings entry, which is what Discord does too.
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
    final order = ChannelSidebarOrder(
      space: space,
      channels: channels,
      categories: categories,
      collapsedCategoryIds: collapsedCategoryIds,
      selectedChannelId: selectedChannelId,
      readState: _readState,
      channelOf: channelOf,
    );
    return Container(
      key: const ValueKey('channel-sidebar'),
      width: 236,
      decoration: BoxDecoration(color: context.surfaces.rail),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No line under the header: the rail side of the window has no
          // dividers, only the canvas card has edges.
          Container(
            height: _SidebarMetrics.headerHeight,
            // The DM search lines up with the rows under it.
            padding: EdgeInsets.symmetric(
              horizontal: isDirect ? _SidebarMetrics.listInset : 16,
            ),
            alignment: Alignment.centerLeft,
            child: isDirect
                ? _DirectMessageSearch(onPressed: onNewDirectMessage)
                : _ServerHeader(
                    title: _spaceTitle(context),
                    onOpenSettings: onOpenServerSettings,
                    onLeave: onLeaveServer,
                    onReport: onReportServer,
                    onOpenNotifications: onNotificationRequest == null
                        ? null
                        : _openSpaceNotifications,
                  ),
          ),
          if (friends case final friends? when isDirect)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _SidebarMetrics.listInset,
              ),
              child: _SidebarNavRow(
                key: const ValueKey('toggle-friends'),
                icon: FlucordIcons.friends,
                label: 'Friends',
                selected: friends.isPanelOpen,
                onPressed: friends.togglePanel,
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
                    padding: const EdgeInsets.fromLTRB(
                      _SidebarMetrics.listInset,
                      0,
                      _SidebarMetrics.listInset,
                      _SidebarMetrics.listInset,
                    ),
                    children: _navigationEntries(context, order),
                  ),
          ),
          // On a short window a tall bar scrolls, so the channels and the
          // account panel keep their place.
          if (voiceConnectionBar case final bar?)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height / 2,
              ),
              child: SingleChildScrollView(child: bar),
            ),
          AccountPanel(
            member: currentMember,
            sessionMode: sessionMode,
            connectionStatus: connectionStatus,
          ),
        ],
      ),
    );
  }

  /// The space's name, with a mark when the whole space is muted. Takes all
  /// the width its row has left.
  Widget _spaceTitle(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          space.name,
          overflow: TextOverflow.ellipsis,
          style: FlucordTextRole.heading.style.copyWith(
            color: _spaceMuted ? context.surfaces.muted : context.surfaces.text,
          ),
        ),
      ),
      if (_spaceMuted)
        Padding(
          key: const ValueKey('space-muted'),
          padding: const EdgeInsetsDirectional.only(end: 4),
          child: FlucordIcon(
            FlucordIcons.silent,
            size: _SidebarMetrics.iconSize,
            color: context.surfaces.muted,
          ),
        ),
    ],
  );

  /// What sits beside the "Direct messages" label: the mark of a muted
  /// space and the space's notification menu. Null when there is neither.
  Widget? _directMessagesLabelTrailing(BuildContext context) {
    final onRequest = onNotificationRequest;
    if (!_spaceMuted && onRequest == null) return null;
    final color = context.surfaces.captionText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_spaceMuted)
          FlucordIcon(
            key: const ValueKey('space-muted'),
            FlucordIcons.silent,
            size: _SidebarMetrics.labelIconSize,
            color: color,
          ),
        if (onRequest != null)
          PopupMenuButton<NotificationMenuRequest>(
            key: const ValueKey('space-notification-menu'),
            tooltip: 'Notification settings',
            iconSize: _SidebarMetrics.labelIconSize,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(_SidebarMetrics.labelButtonSize),
              minimumSize: const Size.square(_SidebarMetrics.labelButtonSize),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: FlucordIcon(FlucordIcons.more, color: color),
            onSelected: (request) => onRequest(request, null),
            itemBuilder: (context) => _spaceNotificationItems,
          ),
      ],
    );
  }

  List<PopupMenuEntry<NotificationMenuRequest>> get _spaceNotificationItems =>
      notificationMenuItems(
        muted: _spaceMuted,
        level: _spaceSettings.messageNotifications,
        isSpaceScope: true,
        suppressEveryone: _spaceSettings.suppressEveryone,
        mobilePush: _spaceSettings.mobilePush,
      );

  /// Raises the notification menu for the whole space at [position].
  Future<void> _openSpaceNotifications(
    BuildContext context,
    RelativeRect position,
  ) async {
    final request = await showMenu<NotificationMenuRequest>(
      context: context,
      position: position,
      items: _spaceNotificationItems,
    );
    if (request != null) onNotificationRequest?.call(request, null);
  }

  ReadStateSnapshot get _readState => readState ?? ReadStateSnapshot.empty;

  GuildNotificationSettings get _spaceSettings =>
      _readState.settingsFor(space.id);

  bool get _spaceMuted => _readState.isSpaceMuted(space.id);

  bool _isMuted(ConversationChannel channel) =>
      _readState.isChannelMuted(channel);

  /// Whether the row should read as unread.
  bool _showsUnread(ConversationChannel channel) =>
      _readState.showsUnread(channel);

  List<Widget> _navigationEntries(
    BuildContext context,
    ChannelSidebarOrder order,
  ) {
    if (space.isDirectMessages) return _directMessageEntries(context, order);
    if (order.categories.isEmpty) {
      return [..._eventEntries(), ..._uncategorizedEntries(order)];
    }
    final uncategorized = order.uncategorized;
    return [
      ..._eventEntries(),
      if (uncategorized.isNotEmpty) ...[
        const _SectionLabel(label: 'Channels'),
        for (final channel in uncategorized) _rowFor(channel),
      ],
      for (final category in order.categories)
        // A category whose every channel was filtered out is dropped whole.
        // Collapsing hides rows without emptying this list, so a collapsed
        // category still keeps its header — only a category the account
        // cannot see into loses one.
        if (order.hasChannelsIn(category))
          _CategorySection(
            category: category,
            collapsed: collapsedCategoryIds.contains(category.id),
            onToggle: () => onToggleCategory(category.id),
            children: [
              // Voice channels carry their occupants here too. They only did
              // outside categories, which is where almost no server puts
              // them, so every seat was invisible in practice.
              for (final channel in order.rowsIn(category))
                if (channel.kind == ChannelKind.voice)
                  ..._voiceEntry(channel)
                else
                  _rowFor(channel),
            ],
          ),
      if (order.threads.isNotEmpty) ...[
        const _SectionLabel(label: 'Active threads'),
        for (final channel in order.threads) _rowFor(channel, indented: true),
      ],
    ];
  }

  /// The direct-messages block: the conversations, with the unanswered
  /// requests folded into their folder.
  ///
  /// A request never sits in the main list. Discord hides it there until the
  /// account answers it, which is the whole point of the folder, so the split
  /// happens here rather than in whatever built the channel list.
  List<Widget> _directMessageEntries(
    BuildContext context,
    ChannelSidebarOrder order,
  ) {
    final requests = order.messageRequests;
    return [
      _DirectMessagesFolder(
        labelTrailing: _directMessagesLabelTrailing(context),
        requests: requests,
        conversationRows: [
          for (final channel in order.conversations) _rowFor(channel),
        ],
        requestRows: [for (final channel in requests) _requestRowFor(channel)],
      ),
    ];
  }

  /// The person a one-to-one DM row shows, or null for a group or a channel.
  Member? _recipientOf(ConversationChannel channel) =>
      switch (channel.soleRecipientId) {
        final id? => memberOf(id),
        null => null,
      };

  _MessageRequestRow _requestRowFor(ConversationChannel channel) =>
      _MessageRequestRow(
        channel: channel,
        recipient: _recipientOf(channel),
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
      Padding(
        padding: const EdgeInsets.only(top: _SidebarMetrics.listInset),
        child: GuildEventsSidebarButton(
          count: scheduledEventCount,
          isLoading: isLoadingScheduledEvents,
          hasError: scheduledEventsError != null,
          onPressed: onOpenEvents ?? () {},
        ),
      ),
    ];
  }

  List<Widget> _uncategorizedEntries(ChannelSidebarOrder order) {
    final text = order.ofKinds(const {ChannelKind.text});
    final voice = order.ofKinds(const {ChannelKind.voice});
    final forums = order.ofKinds(const {ChannelKind.forum, ChannelKind.media});
    return [
      if (text.isNotEmpty) ...[
        const _SectionLabel(label: 'Text channels'),
        for (final channel in text) _rowFor(channel),
      ],
      if (order.threads.isNotEmpty) ...[
        const _SectionLabel(label: 'Active threads'),
        for (final channel in order.threads) _rowFor(channel, indented: true),
      ],
      if (forums.isNotEmpty) ...[
        const _SectionLabel(label: 'Forums'),
        for (final channel in forums) _rowFor(channel),
      ],
      if (voice.isNotEmpty) ...[
        const _SectionLabel(label: 'Voice channels'),
        for (final channel in voice) ..._voiceEntry(channel),
      ],
    ];
  }

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
        speaking: speakingUserIds.contains(seat.userId),
        indented: indented,
        onOpenProfile: onOpenMemberProfile,
      ),
  ];

  _ChannelRow _rowFor(ConversationChannel channel, {bool indented = false}) =>
      _ChannelRow(
        channel: channel,
        selected: channel.id == selectedChannelId,
        recipient: _recipientOf(channel),
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
