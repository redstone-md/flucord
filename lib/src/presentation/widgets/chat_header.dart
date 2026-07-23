import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

class ChatHeader extends StatelessWidget {
  const ChatHeader({
    required this.channel,
    required this.channels,
    required this.query,
    required this.showCompactPicker,
    required this.allowMemberPanel,
    required this.showMembers,
    required this.showPins,
    required this.onSelectChannel,
    required this.onQueryChanged,
    required this.onToggleMembers,
    required this.onTogglePins,
    super.key,
  });

  final ConversationChannel channel;
  final List<ConversationChannel> channels;
  final String query;
  final bool showCompactPicker;
  final bool allowMemberPanel;
  final bool showMembers;
  final bool showPins;
  final ValueChanged<String> onSelectChannel;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleMembers;
  final VoidCallback onTogglePins;

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
                    for (final item in channels)
                      PopupMenuItem(
                        value: item.id,
                        child: Text(
                          '${item.isThread
                              ? 'Thread:'
                              : item.kind == ChannelKind.text
                              ? '#'
                              : 'Voice:'} ${item.name}',
                        ),
                      ),
                  ],
                  icon: const Icon(Icons.menu),
                )
              else
                Icon(
                  channel.isThread
                      ? Icons.forum_outlined
                      : channel.kind == ChannelKind.text
                      ? Icons.tag
                      : Icons.volume_up_outlined,
                  size: 20,
                ),
              const SizedBox(width: 9),
              Text(
                channel.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
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
              if (channel.kind == ChannelKind.text && showSearch)
                SizedBox(
                  width: 190,
                  child: _SearchField(query: query, onChanged: onQueryChanged),
                ),
              if (channel.kind == ChannelKind.text) ...[
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
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.query, required this.onChanged});

  final String query;
  final ValueChanged<String> onChanged;

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
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: 'Search messages',
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
