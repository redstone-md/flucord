import 'dart:async';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../domain/profile_effect.dart';
import 'motion_scope.dart';

/// A profile effect over a card, scaled to the card's width. Place it in a
/// [Stack] over the card, which clips it.
///
/// The layers follow Discord's timing from the moment the effect appears:
/// the intro plays once, then the loop. The clock stops while the window is
/// unfocused or suspended ([TickerMode]), so the effect resumes where it
/// was. Reduced motion draws Discord's still picture instead.
class ProfileEffectOverlay extends StatefulWidget {
  ProfileEffectOverlay({required this.effect, this.endsAt})
    : super(key: ValueKey('profile-effect-${effect.id}'));

  final ProfileEffectConfig effect;

  /// When the effect stops being worn. The overlay goes away then, even on
  /// a card that stays open.
  final DateTime? endsAt;

  @override
  State<ProfileEffectOverlay> createState() => _ProfileEffectOverlayState();
}

class _ProfileEffectOverlayState extends State<ProfileEffectOverlay> {
  late final Ticker _ticker = Ticker(_tick);

  /// The picture each layer draws: its own, or one of its random ones.
  late final Map<ProfileEffectLayer, String> _sources = _pickSources();

  /// Time played before the ticker's current run.
  Duration _played = Duration.zero;
  Duration _run = Duration.zero;
  late Duration? _nextChange = widget.effect.nextChangeAfter(Duration.zero);

  Duration get _elapsed => _played + _run;

  Timer? _expiry;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    if (widget.endsAt case final endsAt?) {
      _expiry = Timer(endsAt.difference(DateTime.now()), () {
        _ticker.stop();
        setState(() => _ended = true);
      });
    }
  }

  Map<ProfileEffectLayer, String> _pickSources() {
    final random = Random();
    return Map.identity()..addAll({
      for (final layer in widget.effect.layers)
        layer: switch (layer.randomizedSources) {
          final List<String> sources when sources.isNotEmpty =>
            sources[random.nextInt(sources.length)],
          _ => layer.src,
        },
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final plays = MotionScope.allows(context);
    if (plays && !_ended && !_ticker.isActive && _nextChange != null) {
      _ticker.start();
    } else if (!plays && _ticker.isActive) {
      _played += _run;
      _run = Duration.zero;
      _ticker.stop();
    }
  }

  void _tick(Duration run) {
    _run = run;
    final next = _nextChange;
    if (next == null || _elapsed < next) return;
    setState(() => _nextChange = widget.effect.nextChangeAfter(_elapsed));
    if (_nextChange == null) _ticker.stop();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ended) return const SizedBox.shrink();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          key: const ValueKey('profile-effect'),
          builder: (context, box) {
            final scale = box.maxWidth / ProfileEffectConfig.canvasWidth;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: still
                  ? [
                      if (widget.effect.stillSrc case final src?)
                        Positioned(
                          left: 0,
                          top: 0,
                          width: box.maxWidth,
                          child: _picture(src, BoxFit.fitWidth),
                        ),
                    ]
                  : [
                      for (final layer in widget.effect.layersAt(_elapsed))
                        Positioned(
                          left: layer.x * scale,
                          top: layer.y * scale,
                          width: layer.width * scale,
                          height: layer.height * scale,
                          child: _picture(_sources[layer]!, BoxFit.fill),
                        ),
                    ],
            );
          },
        ),
      ),
    );
  }

  static Widget _picture(String url, BoxFit fit) => Image.network(
    url,
    fit: fit,
    gaplessPlayback: true,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}
