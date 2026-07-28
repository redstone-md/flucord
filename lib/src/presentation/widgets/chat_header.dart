import 'package:flutter/material.dart';

import '../../application/inbox_catalog.dart';
import '../../application/voice_channel_surface.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'inbox_dialog.dart';
import 'voice_surface_switch.dart';

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
    this.threadMembership,
    this.showVoiceSurfaces = false,
    this.isInCall = false,
    this.callLabel,
    this.onToggleCall,
    super.key,
  });

  final ConversationChannel channel;
  final List<ConversationChannel> channels;
  final String query;
  final bool showCompactPicker;

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

  /// What the call button does right now — start, join, ring, or leave. It is
  /// the button's only label, so it also has to read well to a screen reader.
  final String? callLabel;

  /// Null when the channel cannot be called — a guild channel, or a transport
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
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.surfaces.canvas,
        border: Border(bottom: BorderSide(color: context.surfaces.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showTopic = constraints.maxWidth >= 430;
          final showSearch = constraints.maxWidth >= 610;
          return Row(
            children: [
              if (showCompactPicker)
                PopupMenuButton<String>(
                  tooltip: 'Choose channel',
                  onSelected: onSelectChannel,
                  itemBuilder: (context) => [
                    for (final item in channels.where(
                      (item) => !item.isArchived || item.id == channel.id,
                    ))
                      PopupMenuItem(
                        value: item.id,
                        child: Text('${_channelLabel(item)} ${item.name}'),
                      ),
                  ],
                  icon: const Icon(Icons.menu),
                )
              else
                Icon(_channelIcon(channel), size: 20),
              const SizedBox(width: 9),
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  channel.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (showTopic) ...[
                const SizedBox(width: 14),
                Container(width: 1, height: 20, color: context.surfaces.border),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    channel.topic,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              if (threadMembership case final membership?) ...[
                const SizedBox(width: 4),
                membership,
              ],
              if (onToggleCall != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('toggle-call'),
                  onPressed: onToggleCall,
                  tooltip: callLabel ?? 'Start call',
                  color: isInCall ? FlucordColors.danger : null,
                  icon: Icon(isInCall ? Icons.call_end : Icons.call),
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
              if (showsMessages && showSearch)
                SizedBox(
                  width: 190,
                  child: _SearchField(
                    query: query,
                    onChanged: onQueryChanged,
                    onSubmitted: onSubmitQuery,
                  ),
                ),
              const SizedBox(width: 4),
              InboxActivityButton(
                summary: inboxSummary,
                onPressed: onOpenInbox,
              ),
              if (allowThreadPanel) ...[
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('toggle-threads'),
                  onPressed: onToggleThreads,
                  icon: Icon(
                    showThreads ? Icons.forum : Icons.forum_outlined,
                    size: 19,
                  ),
                  tooltip: showThreads ? 'Close threads' : 'Threads',
                ),
              ],
              // Pinning is absent from the voice text-chat permission set, so
              // the panel and its toggle stay out of a voice channel's chat.
              if (showsMessages && channel.kind != ChannelKind.voice) ...[
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('toggle-pins'),
                  onPressed: onTogglePins,
                  icon: Icon(
                    showPins ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 19,
                  ),
                  tooltip: showPins
                      ? 'Close pinned messages'
                      : 'Pinned messages',
                ),
              ],
              if (allowMemberPanel) ...[
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('toggle-members'),
                  onPressed: onToggleMembers,
                  icon: Icon(showMembers ? Icons.group : Icons.group_outlined),
                  tooltip: showMembers ? 'Hide members' : 'Show members',
                ),
              ],
            ],
          );
        },
      ),
    );
  }

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

  static IconData _channelIcon(ConversationChannel channel) {
    if (channel.isThread) return Icons.forum_outlined;
    if (channel.isDirectMessage) return Icons.person_outline;
    return switch (channel.kind) {
      ChannelKind.text => Icons.tag,
      ChannelKind.voice => Icons.volume_up_outlined,
      ChannelKind.forum => Icons.forum_outlined,
      ChannelKind.media => Icons.perm_media_outlined,
    };
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.query,
    required this.onChanged,
    this.onSubmitted,
  });

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
    return TextField(
      key: const ValueKey('message-search'),
      controller: _controller,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: widget.onSubmitted == null
            ? 'Search messages'
            : 'Search — enter to search the server',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        suffixIcon: _controller.text.isEmpty
            ? const Icon(Icons.search, size: 16)
            : IconButton(
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
                icon: const Icon(Icons.close, size: 15),
                tooltip: 'Clear search',
              ),
      ),
    );
  }
}
