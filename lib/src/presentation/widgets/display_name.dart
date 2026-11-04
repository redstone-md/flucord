import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';

/// A person's name on one line, in the colours they styled it with. The
/// member list, the DM list and message authors all draw names with it.
///
/// Inside a server the role colour wins: the name takes the colour of the
/// member's role, or the plain colour of [style], and the style's colours are
/// not drawn at all. Outside a server they are. This is Discord's own rule:
/// its web client draws the styled name only when there is no guild (the
/// member list item in chunk 110574, `null == guildId && null != styles`)
/// or the channel is private (the message author in chunk 799162,
/// `channel.isPrivate() && null != styles`); elsewhere it passes only the
/// style's font next to the role colour. Source: the web client dump in
/// Wumpus-Central/discrapper-canary.
///
/// No font of Discord's is bundled, so every font id draws the app's font.
class DisplayName extends StatelessWidget {
  const DisplayName(
    this.text, {
    required this.style,
    this.nameStyle,
    this.roleColor,
    this.inServer = false,
    super.key,
  });

  final String text;

  /// The name's type. Its colour is the plain colour.
  final TextStyle style;
  final NameStyle? nameStyle;

  /// The colour of the member's role here, or null for none.
  final int? roleColor;
  final bool inServer;

  @override
  Widget build(BuildContext context) {
    final colors = inServer ? [?roleColor] : _drawableColors(nameStyle);
    return switch (colors) {
      [] => _line(style),
      [final color] => _line(style.copyWith(color: Color(color))),
      _ => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: LinearGradient(
          colors: [for (final color in colors) Color(color)],
        ).createShader,
        child: _line(style),
      ),
    };
  }

  Widget _line(TextStyle style) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);

  /// The colours of [style] this client draws, or none for the plain name.
  ///
  /// Only the two effects that are colour alone are drawn: 1 is solid in the
  /// first colour, 2 a gradient through all of them. The others add a glow,
  /// an outline, a shadow or motion; drawing their colours without that would
  /// be a guess at how Discord's name looks, so they draw the plain name.
  /// Ids from discord-userdoccers, resources/user.mdx "Display Name Effect".
  static List<int> _drawableColors(NameStyle? style) => switch (style) {
    NameStyle(effectId: 1, colors: [final first, ...]) => [first],
    NameStyle(effectId: 2, :final colors) => colors,
    _ => const [],
  };
}
