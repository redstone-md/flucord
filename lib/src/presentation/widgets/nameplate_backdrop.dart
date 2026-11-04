import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/discord/discord_cdn.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_radius.dart';
import 'name_style_scope.dart';
import 'nameplate_motion.dart';

/// The list a nameplate stands in.
enum NameplatePlacement { memberList, directMessages }

/// The palette wash under a nameplate.
///
/// Discord's web client paints it in the member list and the DM list as
/// `linear-gradient(90deg, transparent 0%, c 8% at 20% and 50%, c at 100%)`.
/// The end is 20 % strong at rest, 30 % under the pointer in the member list,
/// and 50 % on the selected row. `c` is the palette's dark colour in a dark
/// theme and its light colour in a light one. Source: chunk 351952 of the web
/// client dump in Wumpus-Central/discrapper-canary.
final class NameplateWash {
  NameplateWash(
    NameplatePalette palette, {
    required Brightness brightness,
    required NameplatePlacement placement,
    bool hovered = false,
    bool selected = false,
  }) : color = brightness == Brightness.dark
           ? palette._darkBackground
           : palette._lightBackground,
       _end = selected
           ? 0x80
           : hovered && placement == NameplatePlacement.memberList
           ? 0x4D
           : 0x33;

  final Color color;

  /// The strength at the row's end, out of 255.
  final int _end;

  /// The strength the plate keeps under the row's text. Discord keeps 30 %.
  /// This theme's muted text sits close to 4.5:1 on its rows already (about
  /// 4.6 on the open DM row in the light theme), so even a 3 % wash under it
  /// falls short. The plate starts where the text ends.
  static const underText = 0.0;

  LinearGradient get gradient => LinearGradient(
    colors: [
      color.withAlpha(0),
      color.withAlpha(0x14),
      color.withAlpha(0x14),
      color.withAlpha(_end),
    ],
    stops: const [0, 0.2, 0.5, 1],
  );

  /// The strongest the wash gets under the row's text.
  Color get strongestUnderText =>
      color.withValues(alpha: _end / 255 * underText);
}

/// Discord's palette colours, from the web client's palette table (chunk
/// 641886 of Wumpus-Central/discrapper-canary; Aliucord's
/// NameplatePalette.kt carries the same values).
extension on NameplatePalette {
  Color get _darkBackground => switch (this) {
    NameplatePalette.crimson => const Color(0xFF900007),
    NameplatePalette.berry => const Color(0xFF893A99),
    NameplatePalette.sky => const Color(0xFF0080B7),
    NameplatePalette.teal => const Color(0xFF086460),
    NameplatePalette.forest => const Color(0xFF2D5401),
    NameplatePalette.bubbleGum => const Color(0xFFDC3E97),
    NameplatePalette.violet => const Color(0xFF730BC8),
    NameplatePalette.cobalt => const Color(0xFF0131C2),
    NameplatePalette.clover => const Color(0xFF047B20),
    NameplatePalette.lemon => const Color(0xFFF6CD12),
    NameplatePalette.white => const Color(0xFFFFFFFF),
  };

  Color get _lightBackground => switch (this) {
    NameplatePalette.crimson => const Color(0xFFE7040F),
    NameplatePalette.berry => const Color(0xFFB11FCF),
    NameplatePalette.sky => const Color(0xFF56CCFF),
    NameplatePalette.teal => const Color(0xFF7DEED7),
    NameplatePalette.forest => const Color(0xFF6AA624),
    NameplatePalette.bubbleGum => const Color(0xFFF957B3),
    NameplatePalette.violet => const Color(0xFF972FED),
    NameplatePalette.cobalt => const Color(0xFF4278FF),
    NameplatePalette.clover => const Color(0xFF63CD5A),
    NameplatePalette.lemon => const Color(0xFFFED400),
    NameplatePalette.white => const Color(0xFFFFFFFF),
  };
}

/// Draws a nameplate behind a row of the member list or the DM list.
///
/// As Discord's clients draw it: the still picture as tall as the row and
/// 16:3 wide, against the row's end and cut to the row's shape (the mobile
/// client's Nameplate.tsx in Wumpus-Central/discord-mobile-datamining), over
/// the palette wash. The plate is held back under the text marked with
/// [NameplateText] ([NameplateWash.underText]) and comes to full strength
/// over the 50 px after it (the web client's mask in chunk 351952), so the
/// text stays readable.
///
/// Under the pointer the moving nameplate plays over the still picture,
/// through the [NameplateMotion] of the [NameStyleScope] above, which plays
/// one at a time. It does not play under reduced motion, or before the still
/// picture has shown, so a picture that failed stays a blank.
class NameplateBackdrop extends StatefulWidget {
  const NameplateBackdrop({
    required this.nameplate,
    required this.placement,
    required this.child,
    this.selected = false,
    super.key,
  });

  final Nameplate nameplate;
  final NameplatePlacement placement;
  final bool selected;
  final Widget child;

  static const _aspectRatio = 16 / 3;
  static const _fade = 50.0;

  @override
  State<NameplateBackdrop> createState() => _NameplateBackdropState();
}

class _NameplateBackdropState extends State<NameplateBackdrop> {
  final _textKey = GlobalKey(debugLabel: 'nameplate text');
  bool _hovered = false;

  /// Whether the still picture has drawn. Set while building it.
  bool _stillShown = false;
  NameplateMotion? _motion;

  bool get _stillOnly => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = NameStyleScope.motionOf(context);
    if (motion != _motion) {
      _motion?.removeListener(_redraw);
      _motion?.stop(this);
      _motion = motion?..addListener(_redraw);
    }
    if (_stillOnly) _motion?.stop(this);
  }

  @override
  void didUpdateWidget(NameplateBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nameplate.asset != widget.nameplate.asset) {
      _stillShown = false;
      _motion?.stop(this);
    }
  }

  @override
  void dispose() {
    _motion?.removeListener(_redraw);
    _motion?.stop(this);
    super.dispose();
  }

  void _redraw() => setState(() {});

  void _enter() {
    final moving = DiscordCdn.movingNameplate(widget.nameplate.asset);
    if (_stillShown && !_stillOnly && moving != null) {
      _motion?.play(this, moving);
    }
    setState(() => _hovered = true);
  }

  void _exit() {
    _motion?.stop(this);
    setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final url = DiscordCdn.nameplate(widget.nameplate.asset);
    final video = _stillOnly ? null : _motion?.videoFor(this);
    final palette = widget.nameplate.palette;
    final wash = palette == null
        ? null
        : NameplateWash(
            palette,
            brightness: Theme.of(context).brightness,
            placement: widget.placement,
            hovered: _hovered,
            selected: widget.selected,
          );
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: FlucordRadius.control,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: _fadeBehindText,
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    fit: StackFit.expand,
                    children: [
                      if (wash != null)
                        DecoratedBox(
                          decoration: BoxDecoration(gradient: wash.gradient),
                        ),
                      if (url != null)
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: 0,
                          width:
                              constraints.maxHeight *
                              NameplateBackdrop._aspectRatio,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                url,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.medium,
                                excludeFromSemantics: true,
                                frameBuilder: (_, child, frame, synchronous) {
                                  _stillShown = frame != null || synchronous;
                                  return child;
                                },
                                errorBuilder: (_, _, _) {
                                  _stillShown = false;
                                  return const SizedBox.shrink();
                                },
                              ),
                              ?video?.view(),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _NameplateScope(textKey: _textKey, child: widget.child),
        ],
      ),
    );
  }

  /// The mask over the plate: faint up to the text's end, full 50 px later.
  Shader _fadeBehindText(Rect bounds) {
    final width = math.max(bounds.width, 1);
    final textEnd = _textEnd();
    final start = (textEnd / width).clamp(0.0, 1.0);
    final end = ((textEnd + NameplateBackdrop._fade) / width).clamp(start, 1.0);
    return LinearGradient(
      colors: [
        Colors.black.withValues(alpha: NameplateWash.underText),
        Colors.black.withValues(alpha: NameplateWash.underText),
        Colors.black,
      ],
      stops: [0, start, end],
    ).createShader(bounds);
  }

  /// Where the marked text ends, from the row's start, or the start for a
  /// row with no marked text. The text's box may stretch to the row's end,
  /// so its widest line is what counts.
  double _textEnd() {
    final text = _textKey.currentContext?.findRenderObject();
    final row = context.findRenderObject();
    if (text is! RenderBox || row is! RenderBox || !text.hasSize) return 0;
    final width = math.min(
      text.size.width,
      text.getMaxIntrinsicWidth(text.size.height),
    );
    return text.localToGlobal(Offset(width, 0), ancestor: row).dx;
  }
}

class _NameplateScope extends InheritedWidget {
  const _NameplateScope({required this.textKey, required super.child});

  final GlobalKey textKey;

  @override
  bool updateShouldNotify(_NameplateScope oldWidget) =>
      textKey != oldWidget.textKey;
}

/// Marks the text a [NameplateBackdrop] keeps readable. Without a backdrop
/// above it, it is only [child].
class NameplateText extends StatelessWidget {
  const NameplateText({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_NameplateScope>();
    return scope == null
        ? child
        : KeyedSubtree(key: scope.textKey, child: child);
  }
}
