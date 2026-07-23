import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import 'remote_identity_image.dart';

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    required this.member,
    this.size = 36,
    this.showPresence = true,
    this.spaceId,
    super.key,
  });

  final Member member;
  final double size;
  final bool showPresence;
  final String? spaceId;

  @override
  Widget build(BuildContext context) {
    final presenceColor = switch (member.presence) {
      Presence.online => const Color(0xff4c9b72),
      Presence.idle => const Color(0xffb87945),
      Presence.offline => const Color(0xff777c79),
    };
    return SizedBox.square(
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
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size * 0.32,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showPresence)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.29,
                height: size * 0.29,
                decoration: BoxDecoration(
                  color: presenceColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
