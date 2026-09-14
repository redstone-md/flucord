import 'package:flutter/material.dart';

import '../../domain/discord_relationship.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';

class DiscordRelationshipAvatar extends StatelessWidget {
  const DiscordRelationshipAvatar({
    required this.user,
    this.size = 36,
    this.presenceBorderColor,
    super.key,
  });

  final DiscordRelationshipUser user;
  final double size;
  final Color? presenceBorderColor;

  @override
  Widget build(BuildContext context) {
    final statusSize = (size * 0.3).clamp(10.0, 18.0);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          ClipOval(
            child: RemoteIdentityImage(
              url: user.avatarUrl,
              fallback: ColoredBox(
                color: context.surfaces.raised,
                child: Center(
                  child: Text(
                    user.displayName.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontSize: size * 0.38,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: statusSize,
              height: statusSize,
              decoration: BoxDecoration(
                color: _presenceColor(context, user.status),
                shape: BoxShape.circle,
                border: Border.all(
                  color: presenceBorderColor ?? context.surfaces.canvas,
                  width: size >= 60 ? 3 : 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _presenceColor(
    BuildContext context,
    DiscordPresenceStatus status,
  ) => switch (status) {
    DiscordPresenceStatus.online => FlucordColors.success,
    DiscordPresenceStatus.idle => FlucordColors.warning,
    DiscordPresenceStatus.doNotDisturb => FlucordColors.danger,
    DiscordPresenceStatus.offline ||
    DiscordPresenceStatus.unknown => context.surfaces.muted,
  };
}
