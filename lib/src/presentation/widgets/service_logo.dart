import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../domain/account_connections.dart';
import '../../theme/flucord_icons.dart';

/// The logo of the service Discord calls [type], in one colour.
///
/// This is the one place a connection's service becomes a picture. Logos
/// come from Hugeicons where it has the brand, and otherwise from Simple
/// Icons (CC0), bundled in `assets/logos`. A type Flucord does not know
/// draws a plain link.
class ServiceLogo extends StatelessWidget {
  const ServiceLogo(this.type, {required this.size, this.color, super.key});

  final String type;
  final double size;

  /// Null takes the icon theme's colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? IconTheme.of(context).color;
    return switch (_logoOf(ConnectionService.byType(type))) {
      _Huge(:final data) => FlucordIcon(
        FlucordIconData(data),
        size: size,
        color: color,
      ),
      // Simple Icons fill their whole square. The inset matches the margin
      // Hugeicons leave around a stroke icon.
      _Simple(:final slug) => SizedBox.square(
        dimension: size,
        child: Padding(
          padding: EdgeInsets.all(size / 12),
          child: SvgPicture.asset(
            'assets/logos/$slug.svg',
            excludeFromSemantics: true,
            colorFilter: color == null
                ? null
                : ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ),
      ),
    };
  }

  static _Logo _logoOf(ConnectionService? service) => switch (service) {
    null => const _Huge(HugeIcons.strokeRoundedLink01),
    ConnectionService.amazonMusic => const _Simple('amazonmusic'),
    ConnectionService.battlenet => const _Simple('battledotnet'),
    ConnectionService.bluesky => const _Huge(HugeIcons.strokeRoundedBluesky),
    ConnectionService.bungie => const _Simple('bungie'),
    ConnectionService.crunchyroll => const _Simple('crunchyroll'),
    ConnectionService.domain => const _Huge(HugeIcons.strokeRoundedGlobe02),
    ConnectionService.ebay => const _Simple('ebay'),
    ConnectionService.epicgames => const _Simple('epicgames'),
    ConnectionService.facebook => const _Huge(
      HugeIcons.strokeRoundedFacebook01,
    ),
    ConnectionService.github => const _Huge(HugeIcons.strokeRoundedGithub),
    ConnectionService.instagram => const _Huge(
      HugeIcons.strokeRoundedInstagram,
    ),
    ConnectionService.leagueoflegends => const _Simple('leagueoflegends'),
    ConnectionService.mastodon => const _Huge(HugeIcons.strokeRoundedMastodon),
    ConnectionService.paypal => const _Huge(HugeIcons.strokeRoundedPaypal),
    ConnectionService.playstation => const _Simple('playstation'),
    ConnectionService.reddit => const _Huge(HugeIcons.strokeRoundedReddit),
    ConnectionService.riotgames => const _Simple('riotgames'),
    ConnectionService.roblox => const _Huge(HugeIcons.strokeRoundedRoblox),
    ConnectionService.skype => const _Huge(HugeIcons.strokeRoundedSkype),
    ConnectionService.spotify => const _Huge(HugeIcons.strokeRoundedSpotify),
    ConnectionService.steam => const _Simple('steam'),
    ConnectionService.tiktok => const _Huge(HugeIcons.strokeRoundedTiktok),
    ConnectionService.twitch => const _Huge(HugeIcons.strokeRoundedTwitch),
    ConnectionService.twitter => const _Huge(HugeIcons.strokeRoundedNewTwitter),
    ConnectionService.xbox => const _Simple('xbox'),
    ConnectionService.youtube => const _Huge(HugeIcons.strokeRoundedYoutube),
  };
}

sealed class _Logo {
  const _Logo();
}

/// A Hugeicons drawing.
final class _Huge extends _Logo {
  const _Huge(this.data);

  final List<List<dynamic>> data;
}

/// A Simple Icons file, by its slug.
final class _Simple extends _Logo {
  const _Simple(this.slug);

  final String slug;
}
