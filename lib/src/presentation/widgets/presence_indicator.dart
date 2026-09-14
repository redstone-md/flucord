import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

/// The status glyph Discord paints on an avatar.
///
/// Colour alone is not enough. Discord gives every status a distinct shape —
/// a filled disc, a crescent, a barred disc, a hollow ring, a rounded square
/// for streaming and a phone outline for mobile — precisely so the four
/// statuses stay apart for a viewer who cannot separate green from red. Drawing
/// them as coloured circles would lose that, so the shape is painted here
/// rather than approximated with an icon font.
class PresenceIndicator extends StatelessWidget {
  const PresenceIndicator({
    required this.presence,
    this.size = 10,
    this.borderColor,
    this.borderWidth = 2,
    super.key,
  });

  final UserPresence presence;
  final double size;
  final Color? borderColor;
  final double borderWidth;

  static Color colorOf(Presence status) => switch (status) {
    Presence.online => FlucordColors.success,
    Presence.idle => FlucordColors.warning,
    Presence.doNotDisturb => FlucordColors.danger,
    Presence.streaming => FlucordColors.brand,
    Presence.offline ||
    Presence.invisible ||
    Presence.unknown => FlucordColors.offline,
  };

  /// What a screen reader announces, mobile included.
  static String labelOf(UserPresence presence) {
    final status = presence.displayStatus.label;
    return presence.isMobileOnly ? '$status on mobile' : status;
  }

  @override
  Widget build(BuildContext context) {
    final status = presence.displayStatus;
    return Semantics(
      label: labelOf(presence),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _PresencePainter(
            status: status,
            mobile: presence.isMobileOnly,
            color: colorOf(status),
            borderColor:
                borderColor ?? Theme.of(context).scaffoldBackgroundColor,
            borderWidth: borderWidth,
          ),
        ),
      ),
    );
  }
}

class _PresencePainter extends CustomPainter {
  const _PresencePainter({
    required this.status,
    required this.mobile,
    required this.color,
    required this.borderColor,
    required this.borderWidth,
  });

  final Presence status;
  final bool mobile;
  final Color color;
  final Color borderColor;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Rect.fromLTWH(0, 0, size.width, size.height);
    final inset = outer.deflate(borderWidth);
    if (inset.isEmpty) return;
    canvas.drawPath(_outerPath(outer), Paint()..color = borderColor);
    canvas.drawPath(_glyph(inset), Paint()..color = color);
  }

  Path _outerPath(Rect outer) => mobile
      ? (Path()..addRRect(
          RRect.fromRectAndRadius(outer, Radius.circular(outer.width * 0.3)),
        ))
      : (Path()..addOval(outer));

  /// The coloured part, cut to the shape the status is recognised by.
  Path _glyph(Rect inset) {
    if (mobile) return _mobileGlyph(inset);
    return switch (status) {
      Presence.idle => _crescent(inset),
      Presence.doNotDisturb => _barred(inset),
      Presence.offline ||
      Presence.invisible ||
      Presence.unknown => _ring(inset),
      Presence.streaming => _streaming(inset),
      Presence.online => Path()..addOval(inset),
    };
  }

  /// A disc with a bite taken out of its top-right, which is how Discord
  /// distinguishes idle from online without relying on the colour.
  Path _crescent(Rect inset) => Path.combine(
    PathOperation.difference,
    Path()..addOval(inset),
    Path()..addOval(
      Rect.fromCircle(
        center: Offset(
          inset.left + inset.width * 0.28,
          inset.top + inset.height * 0.28,
        ),
        radius: inset.width * 0.42,
      ),
    ),
  );

  /// A disc crossed by a horizontal bar.
  Path _barred(Rect inset) => Path.combine(
    PathOperation.difference,
    Path()..addOval(inset),
    Path()..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: inset.center,
          width: inset.width * 0.62,
          height: math.max(inset.height * 0.24, 1),
        ),
        Radius.circular(inset.height * 0.12),
      ),
    ),
  );

  /// A hollow ring: offline is an outline, never a filled dot.
  Path _ring(Rect inset) => Path.combine(
    PathOperation.difference,
    Path()..addOval(inset),
    Path()..addOval(inset.deflate(inset.width * 0.28)),
  );

  /// A rounded square with a play triangle punched out of it.
  Path _streaming(Rect inset) {
    final triangle = Path()
      ..moveTo(inset.left + inset.width * 0.38, inset.top + inset.height * 0.28)
      ..lineTo(inset.left + inset.width * 0.74, inset.center.dy)
      ..lineTo(inset.left + inset.width * 0.38, inset.top + inset.height * 0.72)
      ..close();
    return Path.combine(
      PathOperation.difference,
      Path()..addRRect(
        RRect.fromRectAndRadius(inset, Radius.circular(inset.width * 0.3)),
      ),
      triangle,
    );
  }

  /// A phone outline. Discord replaces the whole dot with it, rather than
  /// adding a second badge, so a mobile-only friend reads as one glyph.
  Path _mobileGlyph(Rect inset) {
    final body = RRect.fromRectAndRadius(
      inset,
      Radius.circular(inset.width * 0.28),
    );
    final screen = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        inset.left + inset.width * 0.22,
        inset.top + inset.height * 0.16,
        inset.right - inset.width * 0.22,
        inset.bottom - inset.height * 0.28,
      ),
      Radius.circular(inset.width * 0.06),
    );
    return Path.combine(
      PathOperation.difference,
      Path()..addRRect(body),
      Path()..addRRect(screen),
    );
  }

  @override
  bool shouldRepaint(_PresencePainter oldDelegate) =>
      oldDelegate.status != status ||
      oldDelegate.mobile != mobile ||
      oldDelegate.color != color ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.borderWidth != borderWidth;
}
