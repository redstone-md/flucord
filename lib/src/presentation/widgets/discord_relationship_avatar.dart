import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/discord_relationship.dart';
import '../../domain/monogram.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'presence_indicator.dart';
import 'remote_identity_image.dart';

/// Somebody from the friend graph: their picture, or their monogram, with
/// their presence as a badge on it.
class DiscordRelationshipAvatar extends StatelessWidget {
  const DiscordRelationshipAvatar({
    required this.user,
    this.size = 36,
    this.presenceBorderColor,
    this.presence,
    this.showPresence = true,
    super.key,
  });

  final DiscordRelationshipUser user;
  final double size;
  final Color? presenceBorderColor;

  /// The status to badge, for a surface that reads presence from somewhere
  /// other than [user]. Null badges [user]'s own status. An unknown status
  /// gets no badge, rather than one that says offline.
  final Presence? presence;
  final bool showPresence;

  @override
  Widget build(BuildContext context) {
    final statusSize = (size * 0.3).clamp(10.0, 18.0);
    final status = presence ?? user.status.presence;
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
          if (showPresence && status != Presence.unknown)
            Positioned(
              right: 0,
              bottom: 0,
              child: PresenceIndicator(
                presence: UserPresence(status: status),
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
