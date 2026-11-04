import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import 'discord_message_syntax.dart';

/// What a mention reads as, in a message body and in a preview of one.
abstract final class DiscordMentionLabel {
  /// A person goes by the name [spaceId] knows them by.
  static String user(ChatWorkspace workspace, String id, String? spaceId) =>
      '@${workspace.memberOrNull(id)?.displayNameFor(spaceId) ?? 'unknown-user'}';

  static String role(ChatWorkspace workspace, String id) =>
      '@${workspace.roleOrNull(id)?.name ?? 'unknown-role'}';

  static String channel(ChatWorkspace workspace, String id) =>
      '#${workspace.channelOrNull(id)?.name ?? 'unknown-channel'}';
}

/// Where a preview is read: the workspace, and the space whose names apply.
typedef _PreviewPlace = ({ChatWorkspace workspace, String? spaceId});

/// How each marker reads in a preview.
final List<(RegExp, String Function(Match, BuildContext, _PreviewPlace))>
_readings = [
  (
    DiscordMarkers.roleMention,
    (marker, _, place) => DiscordMentionLabel.role(place.workspace, marker[1]!),
  ),
  (
    DiscordMarkers.userMention,
    (marker, _, place) =>
        DiscordMentionLabel.user(place.workspace, marker[1]!, place.spaceId),
  ),
  (
    DiscordMarkers.channelMention,
    (marker, _, place) =>
        DiscordMentionLabel.channel(place.workspace, marker[1]!),
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
/// as a reply preview. Mentions, emoji, commands and timestamps read as words,
/// people by the names [spaceId] knows them by.
String messagePreviewText(
  BuildContext context,
  String body,
  ChatWorkspace workspace, {
  required String? spaceId,
}) => body.replaceAllMapped(_anyMarker, (found) {
  final text = found[0]!;
  for (final (marker, read) in _readings) {
    if (marker.matchAsPrefix(text) case final match?
        when match.end == text.length) {
      return read(match, context, (workspace: workspace, spaceId: spaceId));
    }
  }
  return text;
});
