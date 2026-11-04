import 'package:flutter/material.dart';

import '../../data/discord/discord_cdn.dart';
import '../../domain/chat_models.dart';
import 'presence_indicator.dart';
import 'presence_scope.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'remote_identity_image.dart';

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    required this.member,
    this.size = 36,
    this.showPresence = true,
    this.spaceId,
    this.presenceBorderColor,
    this.livePresence = true,
    this.decorated = false,
    super.key,
  });

  /// How much larger than the avatar Discord draws a decoration, centred on
  /// it.
  static const decorationScale = 1.2;

  final Member member;
  final double size;
  final bool showPresence;
  final String? spaceId;
  final Color? presenceBorderColor;

  /// Whether the badge follows the presence the app holds for [member] now,
  /// through [PresenceScope]. Off for a presence given from elsewhere, such
  /// as the account's own.
  final bool livePresence;

  /// Whether the avatar wears [member]'s decoration, which Discord draws in
  /// message rows, the member list, the DM list and the account panel. It
  /// moves on hover, as an animated avatar does.
  final bool decorated;

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    // A picture, not text: its fallback letters stay out of a selection.
    child: _avatar(context),
  );

  Widget _avatar(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipOval(
            child: RemoteIdentityImage(
              url: member.avatarUrlFor(spaceId),
              imageKey: ValueKey('member-avatar-image-${member.id}'),
              fallback: DecoratedBox(
                decoration: BoxDecoration(color: Color(member.colorValue)),
                child: Center(
                  child: Text(
                    member.initials,
                    softWrap: false,
                    style: TextStyle(
                      color: FlucordFixedColors.onFill,
                      fontSize: FlucordType.fitting(size * 0.32),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (decorated)
          if (member.tags.decoration case final decoration?)
            Positioned(
              left: size * (1 - decorationScale) / 2,
              top: size * (1 - decorationScale) / 2,
              width: size * decorationScale,
              height: size * decorationScale,
              child: RemoteIdentityImage(
                url: DiscordCdn.avatarDecoration(decoration.asset),
                imageKey: ValueKey('member-avatar-decoration-${member.id}'),
                fallback: const SizedBox.shrink(),
              ),
            ),
        if (showPresence)
          Positioned(
            right: -1,
            bottom: -1,
            child: PresenceIndicator(
              key: ValueKey('member-presence-${member.id}'),
              presence:
                  (livePresence
                          ? PresenceScope.memberOf(context, member)
                          : member)
                      .presenceOrCoarse,
              size: size * 0.34,
              borderColor: presenceBorderColor,
            ),
          ),
      ],
    ),
  );
}
