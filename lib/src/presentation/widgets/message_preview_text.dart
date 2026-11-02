import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';

/// What a mention reads as, in a message body and in a preview of one.
abstract final class DiscordMentionLabel {
  static String user(ChatWorkspace workspace, String id) =>
      '@${workspace.memberOrNull(id)?.displayName ?? 'unknown-user'}';

  static String role(ChatWorkspace workspace, String id) =>
      '@${workspace.roleOrNull(id)?.name ?? 'unknown-role'}';

  static String channel(ChatWorkspace workspace, String id) =>
      '#${workspace.channelOrNull(id)?.name ?? 'unknown-channel'}';
}

final _discordMarkup = RegExp(
  r'<@&(?<role>\d+)>'
  r'|<@!?(?<user>\d+)>'
  r'|<#(?<channel>\d+)>'
  r'|<a?:(?<emoji>[A-Za-z0-9_~]+):\d+>'
  r'|</(?<command>[^:>]+):\d+>'
  r'|<t:(?<epoch>\d+)(?::[tTdDfFR])?>',
);

/// [body] as one plain string, for a place too small to draw the message, such
/// as a reply preview. Mentions, emoji, commands and timestamps read as words.
String messagePreviewText(
  BuildContext context,
  String body,
  ChatWorkspace workspace,
) => body.replaceAllMapped(_discordMarkup, (found) {
  final match = found as RegExpMatch;
  if (match.namedGroup('role') case final id?) {
    return DiscordMentionLabel.role(workspace, id);
  }
  if (match.namedGroup('user') case final id?) {
    return DiscordMentionLabel.user(workspace, id);
  }
  if (match.namedGroup('channel') case final id?) {
    return DiscordMentionLabel.channel(workspace, id);
  }
  if (match.namedGroup('emoji') case final name?) return ':$name:';
  if (match.namedGroup('command') case final name?) return '/$name';
  return MaterialLocalizations.of(context).formatMediumDate(
    DateTime.fromMillisecondsSinceEpoch(
      int.parse(match.namedGroup('epoch')!) * 1000,
      isUtc: true,
    ).toLocal(),
  );
});
