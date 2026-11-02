import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import 'discord_message_syntax.dart';

/// What a mention reads as, in a message body and in a preview of one.
abstract final class DiscordMentionLabel {
  static String user(ChatWorkspace workspace, String id) =>
      '@${workspace.memberOrNull(id)?.displayName ?? 'unknown-user'}';

  static String role(ChatWorkspace workspace, String id) =>
      '@${workspace.roleOrNull(id)?.name ?? 'unknown-role'}';

  static String channel(ChatWorkspace workspace, String id) =>
      '#${workspace.channelOrNull(id)?.name ?? 'unknown-channel'}';
}

/// How each marker reads in a preview.
final List<(RegExp, String Function(Match, BuildContext, ChatWorkspace))>
_readings = [
  (
    DiscordMarkers.roleMention,
    (marker, _, workspace) => DiscordMentionLabel.role(workspace, marker[1]!),
  ),
  (
    DiscordMarkers.userMention,
    (marker, _, workspace) => DiscordMentionLabel.user(workspace, marker[1]!),
  ),
  (
    DiscordMarkers.channelMention,
    (marker, _, workspace) =>
        DiscordMentionLabel.channel(workspace, marker[1]!),
  ),
  (DiscordMarkers.emoji, (marker, _, _) => ':${marker[2]}:'),
  (DiscordMarkers.command, (marker, _, _) => '/${marker[1]}'),
  (
    DiscordMarkers.timestamp,
    (marker, context, _) => MaterialLocalizations.of(context).formatMediumDate(
      DateTime.fromMillisecondsSinceEpoch(
        int.parse(marker[1]!) * 1000,
        isUtc: true,
      ).toLocal(),
    ),
  ),
];

final _anyMarker = RegExp(
  _readings.map((reading) => '(?:${reading.$1.pattern})').join('|'),
);

/// [body] as one plain string, for a place too small to draw the message, such
/// as a reply preview. Mentions, emoji, commands and timestamps read as words.
String messagePreviewText(
  BuildContext context,
  String body,
  ChatWorkspace workspace,
) => body.replaceAllMapped(_anyMarker, (found) {
  final text = found[0]!;
  for (final (marker, read) in _readings) {
    if (marker.matchAsPrefix(text) case final match?
        when match.end == text.length) {
      return read(match, context, workspace);
    }
  }
  return text;
});
