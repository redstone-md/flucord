import 'package:flutter/material.dart';

import '../../domain/discord_oauth.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';

class OAuthAccountFooter extends StatelessWidget {
  const OAuthAccountFooter({required this.account, super.key});

  final DiscordOAuthAccount account;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        border: Border(top: BorderSide(color: context.surfaces.border)),
      ),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox.square(
              dimension: 32,
              child: RemoteIdentityImage(
                url: account.avatarUrl,
                fallback: ColoredBox(
                  color: context.surfaces.raised,
                  child: const Icon(Icons.person_outline, size: 18),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '@${account.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.surfaces.muted, fontSize: 10),
                ),
              ],
            ),
          ),
          const Tooltip(
            message: 'Linked Discord identity',
            child: Icon(
              Icons.verified_user_outlined,
              size: 17,
              color: FlucordColors.success,
            ),
          ),
        ],
      ),
    );
  }
}
