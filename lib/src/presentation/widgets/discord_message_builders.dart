import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../data/discord/discord_cdn.dart';
import '../../domain/chat_models.dart';
import '../../domain/duration_in_words.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import 'message_preview_text.dart';
import 'popup_anchor.dart';
import 'profile_card_route.dart';
import 'user_settings_scope.dart';

/// [spaceId] is where the message was sent: a mentioned person goes by the
/// name that space knows them by. [onOpenProfile] opens a mentioned person's
/// card; without it a person's mention is only a label.
Map<String, MarkdownElementBuilder> discordMessageBuilders({
  required ChatWorkspace workspace,
  required String? spaceId,
  required ValueChanged<String> onSelectChannel,
  OpenProfileCard? onOpenProfile,
  DateTime? now,
}) => {
  'discord-user': _MentionBuilder(
    workspace,
    _MentionKind.user,
    spaceId: spaceId,
    onOpenProfile: onOpenProfile,
  ),
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
  _MentionBuilder(
    this._workspace,
    this._kind, {
    this.onSelectChannel,
    this.onOpenProfile,
    this.spaceId,
  });

  final ChatWorkspace _workspace;
  final _MentionKind _kind;
  final ValueChanged<String>? onSelectChannel;
  final OpenProfileCard? onOpenProfile;
  final String? spaceId;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final id = element.attributes['id'] ?? element.textContent;
    final label = switch (_kind) {
      _MentionKind.user => DiscordMentionLabel.user(_workspace, id, spaceId),
      _MentionKind.role => DiscordMentionLabel.role(_workspace, id),
      _MentionKind.channel => DiscordMentionLabel.channel(_workspace, id),
      _MentionKind.broadcast => '@${element.textContent}',
    };
    final roleColor = _kind == _MentionKind.role
        ? _workspace.roleOrNull(id)?.colorValue
        : null;
    final foreground = roleColor == null
        ? context.surfaces.link
        : Color(roleColor);
    final openProfile = onOpenProfile;
    final selectChannel = onSelectChannel;
    // Every channel the workspace knows is reachable, voice included: a voice
    // mention opens that channel's chat, the way it does in Discord. A person
    // opens their card when the workspace knows them.
    final ValueChanged<Rect>? onTap = switch (_kind) {
      _MentionKind.channel
          when selectChannel != null && _workspace.channelOrNull(id) != null =>
        (_) => selectChannel(id),
      _MentionKind.user
          when openProfile != null && _workspace.memberOrNull(id) != null =>
        (anchor) => openProfile(id, anchor),
      _ => null,
    };
    return Semantics(
      button: onTap != null,
      label: label,
      child: _MentionChip(
        key: ValueKey('discord-${_kind.name}-$id'),
        label: label,
        color: foreground,
        style: parentStyle ?? preferredStyle,
        onTap: onTap,
      ),
    );
  }
}

/// A mention's pill. One that leads somewhere fills with the brand colour
/// under the pointer and darkens while pressed, as in Discord. [onTap] gets
/// the pill's rectangle, for a card that opens beside it.
class _MentionChip extends StatefulWidget {
  const _MentionChip({
    required this.label,
    required this.color,
    required this.style,
    required this.onTap,
    super.key,
  });

  final String label;
  final Color color;
  final TextStyle? style;
  final ValueChanged<Rect>? onTap;

  @override
  State<_MentionChip> createState() => _MentionChipState();
}

class _MentionChipState extends State<_MentionChip> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final surfaces = context.surfaces;
    final lit = onTap != null && (_hovered || _pressed);
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: !lit
            ? widget.color.withValues(alpha: 0.16)
            : _pressed
            ? surfaces.brandPressed
            : surfaces.brand,
        borderRadius: FlucordRadius.small,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        child: Text(
          widget.label,
          style: widget.style?.copyWith(
            color: lit ? Colors.white : widget.color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
    if (onTap == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () => onTap(popupAnchorOf(context)),
        child: chip,
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
    // The account's own answer to whether a custom emoji moves, read here so
    // a change from another device repaints the timeline. A still frame is
    // the same emoji's webp form, which is what the animated one's first
    // frame is.
    final plays = UserSettingsScope.displayOf(context).playsAnimatedEmoji;
    return Tooltip(
      message: ':$name:',
      child: SizedBox.square(
        key: ValueKey('discord-emoji-$id'),
        dimension: 20,
        child: Image.network(
          DiscordCdn.customEmoji(id, animated: animated && plays),
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
          borderRadius: FlucordRadius.small,
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
    final words = durationInWords(difference.abs());
    return future ? 'in $words' : '$words ago';
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
      color: context.surfaces.brand.withValues(alpha: 0.14),
      borderRadius: FlucordRadius.small,
    ),
    child: Padding(
      key: ValueKey('discord-command-${element.attributes['id']}'),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: Text(
        '/${element.textContent}',
        style: (parentStyle ?? preferredStyle)?.copyWith(
          color: context.surfaces.link,
          fontWeight: FontWeight.w500,
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
      borderRadius: FlucordRadius.small,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _revealed ? context.surfaces.raised : context.surfaces.muted,
          borderRadius: FlucordRadius.small,
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
