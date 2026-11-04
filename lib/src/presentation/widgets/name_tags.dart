import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'remote_identity_image.dart';

/// The tags drawn after a name: the clan chip, then APP for a bot. Draws
/// nothing when [member] has neither.
///
/// Place it right after the name in a row. It brings its own gap.
class NameTags extends StatelessWidget {
  const NameTags({required this.member, this.showsClan = true, super.key});

  static const _gap = 4.0;

  final Member member;

  /// Whether the clan chip shows. A reply line has no room for it.
  final bool showsClan;

  @override
  Widget build(BuildContext context) {
    final clan = showsClan ? member.clanTag : null;
    if (clan == null && !member.isBot) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (clan != null) ...[
          const SizedBox(width: _gap),
          ClanTagChip(clan: clan),
        ],
        if (member.isBot) ...[const SizedBox(width: _gap), const AppTag()],
      ],
    );
  }
}

/// The accent APP tag that marks a bot.
class AppTag extends StatelessWidget {
  const AppTag({super.key});

  static const height = 15.0;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return _TagBox(
      height: height,
      color: surfaces.brandTint,
      child: Text(
        'APP',
        style: _tagStyle(FlucordType.appTag, surfaces.brand),
      ),
    );
  }
}

/// A quiet chip with the clan's badge and its tag. Without a badge, a small
/// accent mark stands in for it.
class ClanTagChip extends StatelessWidget {
  const ClanTagChip({required this.clan, super.key});

  static const height = 16.0;
  static const _badgeSize = 12.0;
  static const _markSize = 6.0;
  static const _gap = 4.0;

  final ClanTag clan;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final badgeUrl = clan.badgeUrl;
    return _TagBox(
      height: height,
      color: surfaces.quietFill,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: _badgeSize,
            child: badgeUrl == null
                ? Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: surfaces.brand,
                        borderRadius: FlucordRadius.full,
                      ),
                      child: const SizedBox.square(dimension: _markSize),
                    ),
                  )
                : RemoteIdentityImage(
                    url: badgeUrl,
                    fallback: const SizedBox.shrink(),
                  ),
          ),
          const SizedBox(width: _gap),
          Text(
            clan.tag,
            maxLines: 1,
            style: _tagStyle(FlucordType.clanTag, surfaces.muted),
          ),
        ],
      ),
    );
  }
}

/// The shared shape of a tag: fixed height, small radius, centred content.
class _TagBox extends StatelessWidget {
  const _TagBox({
    required this.height,
    required this.color,
    required this.child,
  });

  static const _padding = 4.0;

  final double height;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: _padding),
    decoration: BoxDecoration(color: color, borderRadius: FlucordRadius.small),
    alignment: Alignment.center,
    child: child,
  );
}

/// Tag letters sit on one line as tall as the font, so they centre in the box.
TextStyle _tagStyle(double size, Color color) =>
    FlucordTextRole.caption.style.copyWith(
      fontSize: size,
      height: 1,
      fontWeight: FontWeight.w500,
      color: color,
    );
