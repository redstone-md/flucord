import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/discord_relationship.dart';
import '../../domain/monogram.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'presence_indicator.dart';
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
                    monogramOf(user.displayName),
                    style: TextStyle(
                      color: context.surfaces.text,
                      fontSize: FlucordType.fitting(size * 0.38),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: PresenceIndicator(
              presence: UserPresence(status: user.status.presence),
              size: statusSize,
              borderColor: presenceBorderColor ?? context.surfaces.canvas,
              borderWidth: size >= 60 ? 3 : 2,
            ),
          ),
        ],
      ),
    );
  }
}
