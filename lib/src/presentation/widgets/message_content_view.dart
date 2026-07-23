import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../domain/chat_models.dart';
import '../../domain/external_link_launcher.dart';
import '../../theme/flucord_theme.dart';
import 'discord_message_builders.dart';
import 'discord_message_syntax.dart';

class MessageContentView extends StatefulWidget {
  const MessageContentView({
    required this.body,
    required this.workspace,
    required this.linkLauncher,
    required this.onSelectChannel,
    this.now,
    this.textStyle,
    super.key,
  });

  final String body;
  final ChatWorkspace workspace;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;
  final DateTime? now;
  final TextStyle? textStyle;

  @override
  State<MessageContentView> createState() => _MessageContentViewState();
}

class _MessageContentViewState extends State<MessageContentView> {
  late MarkdownStyleSheet _markdownStyleSheet;
  Timer? _relativeTimestampTimer;
  int _relativeTimestampTick = 0;

  @override
  void initState() {
    super.initState();
    _configureRelativeTimestampTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _markdownStyleSheet = _buildStyleSheet(context);
  }

  @override
  void didUpdateWidget(covariant MessageContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textStyle != widget.textStyle) {
      _markdownStyleSheet = _buildStyleSheet(context);
    }
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
  Widget build(BuildContext context) {
    return SelectionArea(
      child: MarkdownBody(
        key: ValueKey(_resolutionSignature),
        data: widget.body,
        selectable: false,
        softLineBreak: true,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        inlineSyntaxes: discordMessageInlineSyntaxes(),
        builders: discordMessageBuilders(
          workspace: widget.workspace,
          onSelectChannel: widget.onSelectChannel,
          now: widget.now,
        ),
        styleSheet: _markdownStyleSheet,
        onTapLink: (_, href, _) {
          if (href != null) unawaited(_openLink(context, href));
        },
        imageBuilder: (uri, _, alt) => Text(
          alt?.isNotEmpty == true ? alt! : uri.toString(),
          style: const TextStyle(
            color: FlucordColors.signal,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  int get _resolutionSignature {
    final values = <Object?>[
      widget.body,
      widget.now?.millisecondsSinceEpoch,
      _relativeTimestampTick,
    ];
    for (final match in RegExp(r'<@!?(\d+)>').allMatches(widget.body)) {
      final id = match[1]!;
      values.addAll([id, widget.workspace.memberOrNull(id)?.displayName]);
    }
    for (final match in RegExp(r'<@&(\d+)>').allMatches(widget.body)) {
      final id = match[1]!;
      final role = widget.workspace.roleOrNull(id);
      values.addAll([id, role?.name, role?.colorValue]);
    }
    for (final match in RegExp(r'<#(\d+)>').allMatches(widget.body)) {
      final id = match[1]!;
      final channel = widget.workspace.channelOrNull(id);
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

  Future<void> _openLink(BuildContext context, String rawHref) async {
    final uri = Uri.tryParse(rawHref);
    final opened = uri != null && await widget.linkLauncher.open(uri);
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The link could not be opened.')),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    final bodyStyle =
        widget.textStyle ?? const TextStyle(fontSize: 13, height: 1.38);
    final surfaces = context.surfaces;
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: bodyStyle,
      pPadding: EdgeInsets.zero,
      a: bodyStyle.copyWith(
        color: FlucordColors.signal,
        decoration: TextDecoration.underline,
        decorationColor: FlucordColors.signal,
      ),
      code: bodyStyle.copyWith(
        fontFamily: 'Consolas',
        fontSize: 12,
        backgroundColor: surfaces.inset,
      ),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      em: const TextStyle(fontStyle: FontStyle.italic),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
        borderRadius: BorderRadius.circular(4),
      ),
      tableBorder: TableBorder.all(color: surfaces.border),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: surfaces.border)),
      ),
    );
  }
}
