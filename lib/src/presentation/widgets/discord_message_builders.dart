import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../data/discord/discord_cdn.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

Map<String, MarkdownElementBuilder> discordMessageBuilders({
  required ChatWorkspace workspace,
  required ValueChanged<String> onSelectChannel,
  DateTime? now,
}) => {
  'discord-user': _MentionBuilder(workspace, _MentionKind.user),
  'discord-role': _MentionBuilder(workspace, _MentionKind.role),
  'discord-channel': _MentionBuilder(
    workspace,
    _MentionKind.channel,
    onSelectChannel: onSelectChannel,
  ),
  'discord-broadcast': _MentionBuilder(workspace, _MentionKind.broadcast),
  'discord-emoji': _EmojiBuilder(),
  'discord-timestamp': _TimestampBuilder(now ?? DateTime.now()),
  'discord-command': _CommandBuilder(),
  'discord-spoiler': _SpoilerBuilder(),
};

enum _MentionKind { user, role, channel, broadcast }

final class _MentionBuilder extends MarkdownElementBuilder {
  _MentionBuilder(this._workspace, this._kind, {this.onSelectChannel});

  final ChatWorkspace _workspace;
  final _MentionKind _kind;
  final ValueChanged<String>? onSelectChannel;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final id = element.attributes['id'] ?? element.textContent;
    final label = switch (_kind) {
      _MentionKind.user =>
        '@${_workspace.memberOrNull(id)?.displayName ?? 'unknown-user'}',
      _MentionKind.role =>
        '@${_workspace.roleOrNull(id)?.name ?? 'unknown-role'}',
      _MentionKind.channel =>
        '#${_workspace.channelOrNull(id)?.name ?? 'unknown-channel'}',
      _MentionKind.broadcast => '@${element.textContent}',
    };
    final roleColor = _kind == _MentionKind.role
        ? _workspace.roleOrNull(id)?.colorValue
        : null;
    final foreground = roleColor == null
        ? FlucordColors.brand
        : Color(roleColor);
    final channel = _kind == _MentionKind.channel
        ? _workspace.channelOrNull(id)
        : null;
    final enabled = channel != null && channel.kind != ChannelKind.voice;
    return Semantics(
      button: enabled,
      label: label,
      child: InkWell(
        key: ValueKey('discord-${_kind.name}-$id'),
        onTap: enabled ? () => onSelectChannel?.call(id) : null,
        borderRadius: BorderRadius.circular(3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: foreground.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            child: Text(
              label,
              style: (parentStyle ?? preferredStyle)?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _EmojiBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final name = element.textContent;
    final id = element.attributes['id']!;
    final animated = element.attributes['animated'] == 'true';
    return Tooltip(
      message: ':$name:',
      child: SizedBox.square(
        key: ValueKey('discord-emoji-$id'),
        dimension: 20,
        child: Image.network(
          DiscordCdn.customEmoji(id, animated: animated),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(':$name:', style: parentStyle ?? preferredStyle),
          ),
        ),
      ),
    );
  }
}

final class _TimestampBuilder extends MarkdownElementBuilder {
  _TimestampBuilder(this.now);

  final DateTime now;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final epoch = int.parse(element.attributes['epoch']!);
    final value = DateTime.fromMillisecondsSinceEpoch(
      epoch * 1000,
      isUtc: true,
    ).toLocal();
    final localizations = MaterialLocalizations.of(context);
    final label = _format(
      value,
      element.attributes['style']!,
      localizations,
      MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Tooltip(
      message:
          '${localizations.formatFullDate(value)} '
          '${_time(value, localizations, true, withSeconds: true)}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.surfaces.raised,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Padding(
          key: ValueKey('discord-timestamp-$epoch'),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          child: Text(label, style: parentStyle ?? preferredStyle),
        ),
      ),
    );
  }

  String _format(
    DateTime value,
    String style,
    MaterialLocalizations localizations,
    bool use24Hour,
  ) => switch (style) {
    't' => _time(value, localizations, use24Hour),
    'T' => _time(value, localizations, use24Hour, withSeconds: true),
    'd' => localizations.formatShortDate(value),
    'D' => localizations.formatFullDate(value),
    'F' =>
      '${localizations.formatFullDate(value)} '
          '${_time(value, localizations, use24Hour)}',
    'R' => _relative(value),
    _ =>
      '${localizations.formatMediumDate(value)} '
          '${_time(value, localizations, use24Hour)}',
  };

  String _relative(DateTime value) {
    final difference = value.difference(now);
    final future = !difference.isNegative;
    final duration = difference.abs();
    final (amount, unit) = duration.inDays >= 1
        ? (duration.inDays, duration.inDays == 1 ? 'day' : 'days')
        : duration.inHours >= 1
        ? (duration.inHours, duration.inHours == 1 ? 'hour' : 'hours')
        : duration.inMinutes >= 1
        ? (duration.inMinutes, duration.inMinutes == 1 ? 'minute' : 'minutes')
        : (duration.inSeconds, duration.inSeconds == 1 ? 'second' : 'seconds');
    return future ? 'in $amount $unit' : '$amount $unit ago';
  }

  static String _time(
    DateTime value,
    MaterialLocalizations localizations,
    bool use24Hour, {
    bool withSeconds = false,
  }) {
    final base = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: use24Hour,
    );
    if (!withSeconds) return base;
    final seconds = value.second.toString().padLeft(2, '0');
    final markerIndex = base.lastIndexOf(' ');
    if (markerIndex < 0) return '$base:$seconds';
    return '${base.substring(0, markerIndex)}:$seconds'
        '${base.substring(markerIndex)}';
  }
}

final class _CommandBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => DecoratedBox(
    decoration: BoxDecoration(
      color: FlucordColors.brand.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Padding(
      key: ValueKey('discord-command-${element.attributes['id']}'),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: Text(
        '/${element.textContent}',
        style: (parentStyle ?? preferredStyle)?.copyWith(
          color: FlucordColors.brand,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

final class _SpoilerBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => _DiscordSpoiler(
    text: element.textContent,
    style: parentStyle ?? preferredStyle,
  );
}

class _DiscordSpoiler extends StatefulWidget {
  const _DiscordSpoiler({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_DiscordSpoiler> createState() => _DiscordSpoilerState();
}

class _DiscordSpoilerState extends State<_DiscordSpoiler> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: _revealed ? 'Hide spoiler' : 'Reveal spoiler',
    child: InkWell(
      key: const ValueKey('discord-spoiler'),
      onTap: () => setState(() => _revealed = !_revealed),
      borderRadius: BorderRadius.circular(3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _revealed ? context.surfaces.raised : context.surfaces.muted,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          child: Text(
            widget.text,
            style: widget.style?.copyWith(
              color: _revealed
                  ? Theme.of(context).colorScheme.onSurface
                  : context.surfaces.muted,
            ),
          ),
        ),
      ),
    ),
  );
}
