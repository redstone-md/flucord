import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../domain/chat_models.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'discord_message_builders.dart';
import 'discord_message_syntax.dart';
import 'timeline_dependencies.dart';

/// Text in Discord's markup, drawn as chat draws it: markdown, links, custom
/// emoji, mentions and timestamps.
///
/// The parse-and-build core of a message body, with nothing of a channel
/// around it, so a profile's bio draws the same way. What a link does is up
/// to [onTapLink]. Mentions resolve against [workspace]; without one they
/// show as unknown.
class DiscordMarkdown extends StatefulWidget {
  const DiscordMarkdown({
    required this.body,
    required this.onTapLink,
    this.workspace,
    this.spaceId,
    this.onSelectChannel,
    this.now,
    this.textStyle,
    super.key,
  });

  final String body;
  final ValueChanged<String> onTapLink;
  final ChatWorkspace? workspace;

  /// The space whose names mentions read in, or null for each person's own.
  final String? spaceId;
  final ValueChanged<String>? onSelectChannel;
  final DateTime? now;
  final TextStyle? textStyle;

  @override
  State<DiscordMarkdown> createState() => _DiscordMarkdownState();
}

class _DiscordMarkdownState extends State<DiscordMarkdown> {
  /// Anything markdown or Discord could read as markup. A body without any draws
  /// as plain text, with no parsing and no widgets per word. A false match only
  /// costs a parse, while a miss would show raw markers, so this errs wide.
  static final _markup = RegExp(
    // Inline markers, mentions, tags, escapes, entities and spoilers.
    r'[*_~`|<>\[\]\\&@]'
    // Bare links.
    r'|://|www\.'
    // Control characters, which leaves only the new line.
    r'|[\x00-\x09\x0b-\x1f\x7f]'
    // A line with space at either end, which includes a blank line.
    r'|^\s|\s$'
    // A line that starts a heading, a list, a quote or a rule.
    r'|^(?:[#>+=-]|\d+[.)])',
    multiLine: true,
    caseSensitive: false,
  );

  /// Who mentions resolve against when there is no workspace: nobody.
  static final _nobody = ChatWorkspace(
    spaces: const [],
    channels: const [],
    members: const [],
    messages: const [],
    currentMemberId: '',
  );

  /// Built only for a body that needs it, as it is costly per row.
  MarkdownStyleSheet? _markdownStyleSheet;
  Timer? _relativeTimestampTimer;
  int _relativeTimestampTick = 0;

  ChatWorkspace get _workspace => widget.workspace ?? _nobody;

  @override
  void initState() {
    super.initState();
    _configureRelativeTimestampTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _markdownStyleSheet = null;
  }

  @override
  void didUpdateWidget(covariant DiscordMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textStyle != widget.textStyle) _markdownStyleSheet = null;
    if (oldWidget.body != widget.body || oldWidget.now != widget.now) {
      _configureRelativeTimestampTimer();
    }
  }

  @override
  void dispose() {
    _relativeTimestampTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _markup.hasMatch(widget.body)
      ? _markdown(context, widget.body)
      // Takes the full width with the text at its start, as a parsed body
      // does, so a drag from beside the text still starts a selection.
      : Align(
          alignment: AlignmentDirectional.centerStart,
          heightFactor: 1,
          child: Text(widget.body, style: _bodyStyle),
        );

  Widget _markdown(BuildContext context, String body) => MarkdownBody(
    key: ValueKey(Object.hash(_resolutionSignature, body)),
    data: body,
    selectable: false,
    softLineBreak: true,
    extensionSet: md.ExtensionSet.gitHubFlavored,
    inlineSyntaxes: discordMessageInlineSyntaxes(),
    builders: discordMessageBuilders(
      workspace: _workspace,
      spaceId: widget.spaceId,
      onSelectChannel: widget.onSelectChannel ?? (_) {},
      now: widget.now,
    ),
    styleSheet: _markdownStyleSheet ??= _buildStyleSheet(context),
    onTapLink: (_, href, _) {
      if (href != null) widget.onTapLink(href);
    },
    imageBuilder: (uri, _, alt) => Text(
      alt?.isNotEmpty == true ? alt! : uri.toString(),
      style: TextStyle(
        color: context.surfaces.link,
        decoration: TextDecoration.underline,
      ),
    ),
  );

  int get _resolutionSignature {
    final values = <Object?>[
      widget.body,
      widget.now?.millisecondsSinceEpoch,
      _relativeTimestampTick,
    ];
    final mentions = BodyMentions.of(widget.body);
    for (final id in mentions.members) {
      values.addAll([
        id,
        _workspace.memberOrNull(id)?.displayNameFor(widget.spaceId),
      ]);
    }
    for (final id in mentions.roles) {
      final role = _workspace.roleOrNull(id);
      values.addAll([id, role?.name, role?.colorValue]);
    }
    for (final id in mentions.channels) {
      final channel = _workspace.channelOrNull(id);
      values.addAll([id, channel?.name, channel?.kind]);
    }
    return Object.hashAll(values);
  }

  void _configureRelativeTimestampTimer() {
    _relativeTimestampTimer?.cancel();
    _relativeTimestampTimer = null;
    if (widget.now != null || !RegExp(r'<t:\d+:R>').hasMatch(widget.body)) {
      return;
    }
    _relativeTimestampTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _relativeTimestampTick++);
    });
  }

  TextStyle get _bodyStyle =>
      widget.textStyle ??
      const TextStyle(fontSize: FlucordType.body, height: 1.38);

  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    final bodyStyle = _bodyStyle;
    final surfaces = context.surfaces;
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: bodyStyle,
      pPadding: EdgeInsets.zero,
      a: bodyStyle.copyWith(
        color: surfaces.link,
        decoration: TextDecoration.underline,
        decorationColor: surfaces.link,
      ),
      code: bodyStyle.copyWith(
        fontFamily: 'Consolas',
        fontSize: FlucordType.label,
        backgroundColor: surfaces.inset,
      ),
      strong: FlucordType.writtenBold,
      em: const TextStyle(fontStyle: FontStyle.italic),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      h1: FlucordTextRole.display.style,
      h2: FlucordTextRole.title.style,
      h3: FlucordTextRole.heading.style,
      h1Padding: const EdgeInsets.only(bottom: 4),
      h2Padding: const EdgeInsets.only(bottom: 4),
      h3Padding: const EdgeInsets.only(bottom: 2),
      blockSpacing: 5,
      listIndent: 20,
      listBullet: bodyStyle.copyWith(color: surfaces.muted),
      blockquote: bodyStyle.copyWith(color: surfaces.muted),
      blockquotePadding: const EdgeInsets.only(left: 9, top: 2, bottom: 2),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: surfaces.border, width: 3)),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      codeblockDecoration: BoxDecoration(
        color: surfaces.inset,
        border: Border.all(color: surfaces.border),
        borderRadius: FlucordRadius.small,
      ),
      tableBorder: TableBorder.all(color: surfaces.border),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: surfaces.border)),
      ),
    );
  }
}
