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
      child: _TagLabel('APP', size: FlucordType.appTag, color: surfaces.brand),
    );
  }
}

/// A quiet chip with the clan's badge and its tag. Without a badge, a small
/// accent mark stands in for it. Sizes from the "Clan tag" component in the
/// Flucord Figma file.
class ClanTagChip extends StatelessWidget {
  const ClanTagChip({required this.clan, super.key});

  static const height = 16.0;
  static const _badgeSize = 8.0;
  static const _badgeCorner = BorderRadius.all(Radius.circular(2));
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
          ClipRRect(
            key: const ValueKey('clan-tag-mark'),
            borderRadius: _badgeCorner,
            child: SizedBox.square(
              dimension: _badgeSize,
              child: badgeUrl == null
                  ? ColoredBox(color: surfaces.brand)
                  : RemoteIdentityImage(
                      url: badgeUrl,
                      fallback: const SizedBox.shrink(),
                    ),
            ),
          ),
          const SizedBox(width: _gap),
          _TagLabel(clan.tag, size: FlucordType.clanTag, color: surfaces.muted),
        ],
      ),
    );
  }
}

/// The shared shape of a tag: fixed height, a pill, centred content, 4 px
/// before it and 5 px after, as the component has it.
class _TagBox extends StatelessWidget {
  const _TagBox({
    required this.height,
    required this.color,
    required this.child,
  });

  final double height;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.only(left: 4, right: 5),
    decoration: BoxDecoration(color: color, borderRadius: FlucordRadius.full),
    alignment: Alignment.center,
    child: child,
  );
}

/// Tag letters trimmed to their capitals, with 1 px of room below them, as
/// the component's cap height trim does. Centring that box puts the capitals
/// where the eye expects them; Golos Text keeps more room above its capitals
/// than below its baseline, so centring the whole line looks low.
class _TagLabel extends StatelessWidget {
  const _TagLabel(this.text, {required this.size, required this.color});

  static const _roomBelow = 1.0;

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: _roomBelow),
    child: SizedBox(
      height: FlucordType.capHeight(size),
      child: Transform.translate(
        offset: Offset(0, -FlucordType.capTop(size, lineHeight: size)),
        child: Text(
          text,
          maxLines: 1,
          // Drawn past the box, which is only as tall as the capitals.
          overflow: TextOverflow.visible,
          // One line exactly as tall as the letters' size.
          style: FlucordTextRole.caption.style.copyWith(
            fontSize: size,
            height: 1,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ),
    ),
  );
}
