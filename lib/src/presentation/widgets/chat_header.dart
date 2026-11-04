import 'package:flutter/material.dart';

import '../../application/inbox_catalog.dart';
import '../../application/voice_channel_surface.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_icon_button.dart';
import 'flucord_menu.dart';
import 'inbox_dialog.dart';
import 'recessed_field.dart';
import 'voice_surface_switch.dart';

/// The line at the top of the chat: the channel, its topic, the panel
/// buttons, search and the inbox.
///
/// A DM passes the person's avatar as [leading], so the same header shows a
/// person rather than a channel.
class ChatHeader extends StatelessWidget {
  const ChatHeader({
    required this.channel,
    required this.channels,
    required this.query,
    required this.showCompactPicker,
    required this.showsMessages,
    required this.voiceSurface,
    required this.allowMemberPanel,
    required this.allowThreadPanel,
    required this.showMembers,
    required this.showPins,
    required this.showThreads,
    required this.inboxSummary,
    required this.onSelectChannel,
    required this.onSelectVoiceSurface,
    required this.onQueryChanged,
    required this.onSubmitQuery,
    required this.onToggleMembers,
    required this.onTogglePins,
    required this.onToggleThreads,
    required this.onOpenInbox,
    this.leading,
    this.threadMembership,
    this.showVoiceSurfaces = false,
    this.isInCall = false,
    this.callLabel,
    this.onToggleCall,
    super.key,
  });

  /// The header's height. Every column header in the app shares it.
  static const height = 48.0;

  /// What the header keeps for the channel's icon and name.
  static const _minTitleWidth = 120.0;

  static const _searchWidth = 200.0;

  /// The room between two buttons.
  static const _buttonGap = 4.0;

  final ConversationChannel channel;
  final List<ConversationChannel> channels;
  final String query;
  final bool showCompactPicker;

  /// What stands before the name, such as a DM's avatar with its status
  /// dot. Null draws the channel's icon.
  final Widget? leading;

  /// Whether the pane below is currently showing a message timeline. Search and
  /// pins belong to that timeline, so a voice channel earns them only while its
  /// chat surface is the one on screen.
  final bool showsMessages;
  final VoiceChannelSurface voiceSurface;

  /// Whether this channel has a room-and-chat pair to switch between. True for
  /// a voice channel always, and for a DM only while its call is up.
  final bool showVoiceSurfaces;

  /// Whether the local user is sitting in this channel's call, which turns the
  /// call button into a hang-up.
  final bool isInCall;

  /// What the call button does right now: start, join, ring, or leave. It is
  /// the button's only label, so it also has to read well to a screen reader.
  final String? callLabel;

  /// Null when the channel cannot be called: a guild channel, or a transport
  /// with no call plane.
  final VoidCallback? onToggleCall;
  final bool allowMemberPanel;
  final bool allowThreadPanel;
  final bool showMembers;
  final bool showPins;
  final bool showThreads;
  final InboxSummary inboxSummary;

  /// Join/leave for a thread, or null when the channel is not one.
  final Widget? threadMembership;

  final ValueChanged<String> onSelectChannel;
  final ValueChanged<VoiceChannelSurface> onSelectVoiceSurface;
  final ValueChanged<String> onQueryChanged;

  /// Runs the query against the server. Typing filters the messages already on
  /// screen, which is instant but only ever sees the page that is loaded;
  /// pressing enter asks Discord about the whole conversation. Null when the
  /// signed-in transport has no search plane to ask.
  final ValueChanged<String>? onSubmitQuery;
  final VoidCallback onToggleMembers;
  final VoidCallback onTogglePins;
  final VoidCallback onToggleThreads;
  final VoidCallback onOpenInbox;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.surfaces.canvas,
        border: Border(bottom: BorderSide(color: context.surfaces.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showTopic = constraints.maxWidth >= 430;
          final showSearch = constraints.maxWidth >= 610;
          // The controls take their full width first, then the title and the
          // topic share what is left, the topic giving way first. The cap keeps
          // the title readable in a narrow window, where the controls scroll.
          return Row(
            children: [
              Expanded(child: _title(context, showTopic: showTopic)),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (constraints.maxWidth - _minTitleWidth).clamp(
                    0,
                    constraints.maxWidth,
                  ),
                ),
                child: _controls(
                  context,
                  showTopic: showTopic,
                  showSearch: showSearch,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _title(BuildContext context, {required bool showTopic}) {
    final surfaces = context.surfaces;
    return Row(
      children: [
        if (showCompactPicker)
          PopupMenuButton<String>(
            tooltip: 'Choose channel',
            onSelected: onSelectChannel,
            iconSize: FlucordIconButton.iconSize,
            style: FlucordIconButton.squareStyle,
            itemBuilder: (context) => [
              for (final item in channels.where(
                (item) => !item.isArchived || item.id == channel.id,
              ))
                FlucordMenuItem(
                  value: item.id,
                  label: '${_channelLabel(item)} ${item.name}',
                ),
            ],
            icon: const FlucordIcon(FlucordIcons.channels),
          )
        else
          leading ??
              FlucordIcon(
                _channelIcon(channel),
                size: FlucordIconButton.iconSize,
                color: surfaces.muted,
              ),
        const SizedBox(width: 8),
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            channel.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlucordTextRole.heading.style.copyWith(color: surfaces.text),
          ),
        ),
        if (showTopic && channel.topic.isNotEmpty) ...[
          const SizedBox(width: 12),
          Container(
            key: const ValueKey('chat-header-divider'),
            width: 1,
            height: FlucordIconButton.iconSize,
            color: surfaces.border,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              channel.topic,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FlucordTextRole.caption.style.copyWith(
                color: surfaces.captionText,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _controls(
    BuildContext context, {
    required bool showTopic,
    required bool showSearch,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (threadMembership case final membership?) ...[
        const SizedBox(width: _buttonGap),
        membership,
      ],
      if (onToggleCall != null) ...[
        const SizedBox(width: _buttonGap),
        FlucordIconButton(
          key: const ValueKey('toggle-call'),
          onPressed: onToggleCall,
          tooltip: callLabel ?? 'Start call',
          color: isInCall ? context.surfaces.danger : null,
          icon: isInCall ? FlucordIcons.hangUp : FlucordIcons.call,
        ),
      ],
      if (showVoiceSurfaces) ...[
        const SizedBox(width: 8),
        VoiceSurfaceSwitch(
          surface: voiceSurface,
          showLabels: showTopic,
          onChanged: onSelectVoiceSurface,
        ),
      ],
      // Everything past here scrolls rather than overflows. There are up to
      // five more controls and a search field, and a narrow window used to
      // push the last one past the edge and stripe it yellow. The room's own
      // switch stays out of it: a control that has to be scrolled to is one
      // people do not find.
      Flexible(
        fit: FlexFit.loose,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            children: [
              if (allowThreadPanel) ...[
                const SizedBox(width: _buttonGap),
                FlucordIconButton(
                  key: const ValueKey('toggle-threads'),
                  onPressed: onToggleThreads,
                  selected: showThreads,
                  icon: FlucordIcons.threads,
                  tooltip: showThreads ? 'Close threads' : 'Threads',
                ),
              ],
              // Pinning is absent from the voice text-chat permission set, so
              // the panel and its toggle stay out of a voice channel's chat.
              if (showsMessages && channel.kind != ChannelKind.voice) ...[
                const SizedBox(width: _buttonGap),
                FlucordIconButton(
                  key: const ValueKey('toggle-pins'),
                  onPressed: onTogglePins,
                  selected: showPins,
                  icon: FlucordIcons.pin,
                  tooltip: showPins
                      ? 'Close pinned messages'
                      : 'Pinned messages',
                ),
              ],
              if (allowMemberPanel) ...[
                const SizedBox(width: _buttonGap),
                FlucordIconButton(
                  key: const ValueKey('toggle-members'),
                  onPressed: onToggleMembers,
                  selected: showMembers,
                  icon: FlucordIcons.members,
                  tooltip: showMembers ? 'Hide members' : 'Show members',
                ),
              ],
              if (showsMessages && showSearch) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: _searchWidth,
                  child: _SearchField(
                    query: query,
                    onChanged: onQueryChanged,
                    onSubmitted: onSubmitQuery,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              InboxActivityButton(
                summary: inboxSummary,
                onPressed: onOpenInbox,
              ),
            ],
          ),
        ),
      ),
    ],
  );

  static String _channelLabel(ConversationChannel channel) {
    if (channel.isThread) return 'Post:';
    if (channel.isDirectMessage) return '@';
    return switch (channel.kind) {
      ChannelKind.text => '#',
      ChannelKind.voice => 'Voice:',
      ChannelKind.forum => 'Forum:',
      ChannelKind.media => 'Media:',
    };
  }

  static FlucordIconData _channelIcon(ConversationChannel channel) {
    if (channel.isThread) return FlucordIcons.threads;
    if (channel.isDirectMessage) return FlucordIcons.person;
    return switch (channel.kind) {
      ChannelKind.text => FlucordIcons.textChannel,
      ChannelKind.voice => FlucordIcons.voiceChannel,
      ChannelKind.forum => FlucordIcons.threads,
      ChannelKind.media => FlucordIcons.image,
    };
  }
}

/// The header's search: a recessed field that filters the loaded messages as
/// it is typed in, and asks the server on Enter.
class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.query,
    required this.onChanged,
    this.onSubmitted,
  });

  static const _height = 28.0;

  final String query;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    const iconBox = BoxConstraints.tightFor(
      width: FlucordIconButton.size,
      height: _SearchField._height,
    );
    final field = TextField(
      key: const ValueKey('message-search'),
      controller: _controller,
      onChanged: (value) {
        widget.onChanged(value);
        // The clear button shows only while there is text.
        setState(() {});
      },
      onSubmitted: widget.onSubmitted,
      textInputAction: TextInputAction.search,
      textAlignVertical: TextAlignVertical.center,
      style: FlucordTextRole.label.style.copyWith(color: surfaces.text),
      decoration:
          recessedFieldDecoration(
            context,
            borderRadius: FlucordRadius.control,
          ).copyWith(
            hintText: 'Search',
            hintStyle: FlucordTextRole.label.style.copyWith(
              color: surfaces.captionText,
            ),
            constraints: const BoxConstraints.tightFor(
              height: _SearchField._height,
            ),
            contentPadding: EdgeInsets.zero,
            prefixIcon: FlucordIcon(
              FlucordIcons.search,
              size: FlucordIconButton.iconSize,
              color: surfaces.muted,
            ),
            prefixIconConstraints: iconBox,
            suffixIconConstraints: iconBox,
            suffixIcon: _controller.text.isEmpty
                ? null
                : FlucordIconButton(
                    onPressed: () {
                      _controller.clear();
                      widget.onChanged('');
                      setState(() {});
                    },
                    icon: FlucordIcons.clear,
                    tooltip: 'Clear search',
                  ),
          ),
    );
    if (widget.onSubmitted == null) return field;
    return Tooltip(message: 'Press Enter to search the server', child: field);
  }
}
