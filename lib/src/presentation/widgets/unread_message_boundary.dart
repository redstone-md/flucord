import 'package:flutter/material.dart';

import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

class UnreadMessageBoundary extends StatelessWidget {
  const UnreadMessageBoundary({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('unread-message-boundary'),
    container: true,
    excludeSemantics: true,
    label: 'New messages',
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: context.surfaces.mention)),
          const SizedBox(width: 8),
          Text(
            'NEW',
            style: TextStyle(
              color: context.surfaces.mention,
              fontSize: FlucordType.caption,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Offers the way back to the end of the conversation.
///
/// Shown while the newest message is off screen, which is what opening on the
/// unread boundary leaves behind: the reader is part way up their backlog and
/// needs one press to catch up rather than a long scroll.
class JumpToPresentButton extends StatelessWidget {
  const JumpToPresentButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: context.surfaces.canvas,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: context.surfaces.border),
      borderRadius: FlucordRadius.small,
    ),
    child: InkWell(
      key: const ValueKey('jump-to-present'),
      onTap: onPressed,
      borderRadius: FlucordRadius.small,
      child: SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_downward,
                size: 15,
                color: context.surfaces.muted,
              ),
              const SizedBox(width: 5),
              const Text(
                'Jump to present',
                style: TextStyle(
                  fontSize: FlucordType.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class JumpToUnreadButton extends StatelessWidget {
  const JumpToUnreadButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: context.surfaces.canvas,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: context.surfaces.mention),
      borderRadius: FlucordRadius.small,
    ),
    child: InkWell(
      key: const ValueKey('jump-to-unread'),
      onTap: onPressed,
      borderRadius: FlucordRadius.small,
      child: SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_upward,
                size: 15,
                color: context.surfaces.mention,
              ),
              const SizedBox(width: 5),
              Text(
                'Jump to unread',
                style: TextStyle(
                  fontSize: FlucordType.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
