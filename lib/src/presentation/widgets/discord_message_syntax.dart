import 'package:markdown/markdown.dart' as md;

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

final class _DiscordEmojiSyntax extends md.InlineSyntax {
  _DiscordEmojiSyntax() : super(r'<(a?):([A-Za-z0-9_~]+):(\d+)>');

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
  _DiscordRoleMentionSyntax() : super(r'<@&(\d+)>');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text('discord-role', match[1]!)..attributes['id'] = match[1]!,
    );
    return true;
  }
}

final class _DiscordUserMentionSyntax extends md.InlineSyntax {
  _DiscordUserMentionSyntax() : super(r'<@!?(\d+)>');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text('discord-user', match[1]!)..attributes['id'] = match[1]!,
    );
    return true;
  }
}

final class _DiscordChannelMentionSyntax extends md.InlineSyntax {
  _DiscordChannelMentionSyntax() : super(r'<#(\d+)>');

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
  _DiscordTimestampSyntax() : super(r'<t:(\d+)(?::([tTdDfFR]))?>');

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
  _DiscordCommandSyntax() : super(r'</([^:>]+):(\d+)>');

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
