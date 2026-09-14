import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/thread_membership_controller.dart';
import '../../theme/flucord_theme.dart';

/// Join or leave the thread on screen, with how many people are in it.
///
/// Reading a thread and being a member of it are different things in Discord:
/// membership decides whether the thread stays in the sidebar and whether its
/// messages notify. Without this control a thread could only ever be joined by
/// posting in it, which is not a choice a reader should have to make.
class ThreadMembershipButton extends StatelessWidget {
  const ThreadMembershipButton({required this.controller, super.key});

  final ThreadMembershipController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.isSupported || controller.threadId == null) {
      return const SizedBox.shrink();
    }
    final joined = controller.isJoined;
    final count = controller.memberCount;
    return Row(
      key: const ValueKey('thread-membership'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count > 0)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: '$count in this thread',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.group_outlined,
                    size: 14,
                    color: context.surfaces.muted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    key: const ValueKey('thread-member-count'),
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Only for a member: the settings live on the thread member, so
        // muting a thread nobody has joined has nowhere to be kept.
        if (joined)
          IconButton(
            key: const ValueKey('thread-mute-toggle'),
            tooltip: controller.isMuted
                ? 'Notify me about this thread'
                : 'Stop notifying me about this thread',
            icon: Icon(
              controller.isMuted
                  ? Icons.notifications_off
                  : Icons.notifications_none,
              size: 15,
            ),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            onPressed: controller.isBusy
                ? null
                : () => unawaited(
                    controller.setMuted(muted: !controller.isMuted),
                  ),
          ),
        TextButton.icon(
          key: const ValueKey('thread-membership-toggle'),
          onPressed: controller.isBusy
              ? null
              : () => unawaited(controller.toggle()),
          icon: Icon(
            joined ? Icons.notifications_off_outlined : Icons.add,
            size: 15,
          ),
          label: Text(joined ? 'Leave' : 'Join'),
          style: TextButton.styleFrom(
            foregroundColor: joined
                ? context.surfaces.muted
                : Theme.of(context).colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Tooltip(
              message: 'Discord did not accept that.',
              child: Icon(
                Icons.error_outline,
                key: const ValueKey('thread-membership-error'),
                size: 15,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
