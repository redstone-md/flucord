import 'package:markdown/markdown.dart' as md;

import '../../domain/chat_models.dart';

/// Discord's markers in a message body. The markdown syntaxes below, the
/// preview text and the ids a timeline row depends on all read these, so they
/// cannot drift apart.
abstract final class DiscordMarkers {
  /// Group 1 is `a` for an animated emoji, group 2 the name, group 3 the id.
  static final emoji = RegExp(r'<(a?):([A-Za-z0-9_~]+):(\d+)>');

  /// Group 1 is the role id.
  static final roleMention = RegExp(r'<@&(\d+)>');

  /// Group 1 is the user id.
  static final userMention = ChatMessage.memberMention;

  /// Group 1 is the channel id.
  static final channelMention = RegExp(r'<#(\d+)>');

  /// Group 1 is the time in seconds, group 2 the style letter, if any.
  static final timestamp = RegExp(r'<t:(\d+)(?::([tTdDfFR]))?>');

  /// Group 1 is the command name, group 2 its id.
  static final command = RegExp(r'</([^:>]+):(\d+)>');
}

List<md.InlineSyntax> discordMessageInlineSyntaxes() => [
  _DiscordEmojiSyntax(),
  _DiscordRoleMentionSyntax(),
  _DiscordUserMentionSyntax(),
  _DiscordChannelMentionSyntax(),
  _DiscordTimestampSyntax(),
  _DiscordCommandSyntax(),
  _DiscordSpoilerSyntax(),
  _DiscordBroadcastMentionSyntax(),
];

List<md.BlockSyntax> discordMessageBlockSyntaxes() => const [
  _DiscordSubtextSyntax(),
];

/// A line that starts with `-# `, which Discord draws small and muted. The
/// text is kept unparsed here, because it is drawn as markdown of its own.
final class _DiscordSubtextSyntax extends md.BlockSyntax {
  const _DiscordSubtextSyntax();

  static final _line = RegExp(r'^-# +(.*)$');

  @override
  RegExp get pattern => _line;

  @override
  md.Node parse(md.BlockParser parser) {
    final text = pattern.firstMatch(parser.current.content)![1]!;
    parser.advance();
    return md.Element.empty('discord-subtext')..attributes['text'] = text;
  }
}

final class _DiscordEmojiSyntax extends md.InlineSyntax {
  _DiscordEmojiSyntax() : super(DiscordMarkers.emoji.pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text('discord-emoji', match[2]!)
        ..attributes['animated'] = match[1]!.isNotEmpty ? 'true' : 'false'
        ..attributes['id'] = match[3]!,
    );
    return true;
  }
}

final class _DiscordRoleMentionSyntax extends md.InlineSyntax {
  _DiscordRoleMentionSyntax() : super(DiscordMarkers.roleMention.pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text('discord-role', match[1]!)..attributes['id'] = match[1]!,
    );
    return true;
  }
}

final class _DiscordUserMentionSyntax extends md.InlineSyntax {
  _DiscordUserMentionSyntax() : super(DiscordMarkers.userMention.pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text('discord-user', match[1]!)..attributes['id'] = match[1]!,
    );
    return true;
  }
}

final class _DiscordChannelMentionSyntax extends md.InlineSyntax {
  _DiscordChannelMentionSyntax() : super(DiscordMarkers.channelMention.pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text('discord-channel', match[1]!)
        ..attributes['id'] = match[1]!,
    );
    return true;
  }
}

final class _DiscordTimestampSyntax extends md.InlineSyntax {
  _DiscordTimestampSyntax() : super(DiscordMarkers.timestamp.pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text('discord-timestamp', match[1]!)
        ..attributes['epoch'] = match[1]!
        ..attributes['style'] = match[2] ?? 'f',
    );
    return true;
  }
}

final class _DiscordCommandSyntax extends md.InlineSyntax {
  _DiscordCommandSyntax() : super(DiscordMarkers.command.pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text('discord-command', match[1]!)
        ..attributes['id'] = match[2]!,
    );
    return true;
  }
}

final class _DiscordSpoilerSyntax extends md.InlineSyntax {
  _DiscordSpoilerSyntax() : super(r'\|\|(.+?)\|\|');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('discord-spoiler', match[1]!));
    return true;
  }
}

final class _DiscordBroadcastMentionSyntax extends md.InlineSyntax {
  _DiscordBroadcastMentionSyntax() : super(r'@(everyone|here)\b');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('discord-broadcast', match[1]!));
    return true;
  }
}
