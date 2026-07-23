import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

class ChannelSidebar extends StatelessWidget {
  const ChannelSidebar({
    required this.space,
    required this.channels,
    required this.selectedChannelId,
    required this.onSelectChannel,
    super.key,
  });

  final CommunitySpace space;
  final List<ConversationChannel> channels;
  final String selectedChannelId;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    final textChannels = channels
        .where((channel) => channel.kind == ChannelKind.text)
        .toList(growable: false);
    final voiceChannels = channels
        .where((channel) => channel.kind == ChannelKind.voice)
        .toList(growable: false);
    return Container(
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.more_horiz),
                  tooltip: 'Server menu',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
              children: [
                const _SectionLabel(label: 'Text channels'),
                for (final channel in textChannels)
                  _ChannelRow(
                    channel: channel,
                    selected: channel.id == selectedChannelId,
                    onPressed: () => onSelectChannel(channel.id),
                  ),
                if (voiceChannels.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const _SectionLabel(label: 'Voice channels'),
                  for (final channel in voiceChannels)
                    _ChannelRow(
                      channel: channel,
                      selected: channel.id == selectedChannelId,
                      onPressed: () => onSelectChannel(channel.id),
                    ),
                ],
              ],
            ),
          ),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: context.surfaces.inset,
              border: Border(top: BorderSide(color: context.surfaces.border)),
            ),
            child: const Row(
              children: [
                Icon(Icons.sensors, size: 17, color: FlucordColors.signal),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Local transport',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
                Text('READY', style: TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 8, 6),
      child: Text(
        label,
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.selected,
    required this.onPressed,
  });

  final ConversationChannel channel;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? Theme.of(context).colorScheme.onSurface
        : channel.unread
        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.88)
        : context.surfaces.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? context.surfaces.raised : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          key: ValueKey('channel-${channel.id}'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 34,
            child: Row(
              children: [
                SizedBox(
                  width: 3,
                  child: selected
                      ? const ColoredBox(color: FlucordColors.signal)
                      : null,
                ),
                const SizedBox(width: 8),
                Icon(
                  channel.kind == ChannelKind.text
                      ? Icons.tag
                      : Icons.volume_up_outlined,
                  size: 17,
                  color: foreground,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    channel.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13,
                      fontWeight: channel.unread || selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (channel.mentionCount > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FlucordColors.copper,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${channel.mentionCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
