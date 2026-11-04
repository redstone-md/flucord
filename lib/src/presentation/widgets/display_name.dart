import 'package:flutter/material.dart';

import '../../data/discord/display_name_fonts.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'name_effect.dart';
import 'name_style_scope.dart';

/// A person's name in the font, colours and effect they styled it with. The
/// member list, the DM list, message authors and the profile all draw names
/// with it.
///
/// Inside a server the role colour wins over the style's colours and effect;
/// the font is drawn in both. Discord's web client has the same rule (chunks
/// 110574 and 799162 of Wumpus-Central/discrapper-canary).
///
/// Until its font is ready ([DisplayNameFonts]) the name is in the app font.
/// Fonts and effects this client does not know draw the plain name.
class DisplayName extends StatelessWidget {
  const DisplayName(
    this.text, {
    required this.style,
    this.nameStyle,
    this.inServer,
    this.maxLines = 1,
    super.key,
  });

  final String text;

  /// The name's type. Its colour is the plain colour.
  final TextStyle style;
  final NameStyle? nameStyle;

  /// The server the name is drawn in, or null outside any server.
  final InServer? inServer;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final typed = _inFont(context);
    if (inServer case final server?) {
      return _line(switch (server.roleColor) {
        final color? => typed.copyWith(color: Color(color)),
        null => typed,
      });
    }
    return switch ((NameEffect.byId(nameStyle?.effectId), nameStyle?.colors)) {
      (final effect?, final colors?) when colors.isNotEmpty => _drawn(
        effect.look(colors, context.surfaces),
        typed,
      ),
      _ => _line(typed),
    };
  }

  /// [style] in the person's font, once the [NameStyleScope] above has it.
  /// Until then the name keeps the app font and its spacing, so it does not
  /// change width before the font lands.
  TextStyle _inFont(BuildContext context) {
    final font = DisplayNameFont.byId(nameStyle?.fontId);
    final fonts = NameStyleScope.fontsOf(context);
    if (font == null || fonts == null) return style;
    fonts.request(font);
    final family = fonts.familyOf(font);
    if (family == null) return style;
    return style.copyWith(
      fontFamily: family,
      // Letters the font lacks are drawn in the app font.
      fontFamilyFallback: const [FlucordType.family],
      letterSpacing: font.letterSpacing * _fontSize,
    );
  }

  /// The size the engine draws [style] at.
  double get _fontSize => style.fontSize ?? kDefaultFontSize;

  /// The name drawn with [look]: the drop and the outline under the fill.
  Widget _drawn(NameLook look, TextStyle typed) {
    final outline = look.outline;
    final drop = look.drop;
    final fill = switch (look.stops) {
      [final color] => _line(typed.copyWith(color: color)),
      final stops => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: LinearGradient(
          begin: look.fillFrom,
          end: look.fillTo,
          colors: stops,
        ).createShader,
        child: _line(typed),
      ),
    };
    if (outline == null && drop == null) return fill;
    final width = look.outlineWidth(_fontSize);
    return Stack(
      children: [
        if (drop != null)
          Transform.translate(
            offset: Offset(0, width),
            child: Stack(
              children: [
                _outlined(typed, drop, width),
                ExcludeSemantics(child: _line(typed.copyWith(color: drop))),
              ],
            ),
          ),
        if (outline != null)
          _outlined(
            typed,
            outline,
            width,
            glow: switch (look.glow) {
              final glow? => Shadow(
                color: glow,
                blurRadius: NameLook.glowBlur(_fontSize),
              ),
              null => null,
            },
          ),
        fill,
      ],
    );
  }

  /// The name's outline in [color], [width] wide, with an optional [glow].
  Widget _outlined(
    TextStyle typed,
    Color color,
    double width, {
    Shadow? glow,
  }) => ExcludeSemantics(
    child: _line(
      typed.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round
          ..color = color,
        shadows: [?glow],
      ),
    ),
  );

  Widget _line(TextStyle style) => Text(
    text,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}

/// A name drawn in a server, where the role colour wins over the name's
/// style.
@immutable
final class InServer {
  const InServer({this.roleColor});

  /// The colour of the member's role here, or null for none.
  final int? roleColor;
}
