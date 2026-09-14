import 'package:flutter/material.dart';

import '../../application/direct_call_controller.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';

/// The surface an incoming DM or group-DM call raises.
///
/// It floats over the workspace rather than living inside the conversation
/// pane because a ring is not addressed to whatever channel happens to be open:
/// the call can arrive while the user is three guilds away, and burying the
/// answer behind a navigation step is the one thing a ringing phone must not
/// do. Only the card takes hits, so the workspace underneath stays usable while
/// it is up.
class IncomingCallOverlay extends StatelessWidget {
  const IncomingCallOverlay({
    required this.controller,
    required this.workspace,
    super.key,
  });

  final DirectCallController controller;
  final ChatWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final call = controller.incomingCall;
        if (call == null) return const SizedBox.shrink();
        return Positioned(
          top: 14,
          left: 0,
          right: 0,
          child: Center(
            child: IncomingCallCard(
              caller: workspace.memberOrNull(call.callerId),
              channelName: workspace.channelOrNull(call.channelId)?.name,
              isBusy: controller.isBusy,
              onAccept: controller.acceptIncomingCall,
              onDecline: controller.declineIncomingCall,
            ),
          ),
        );
      },
    );
  }
}

/// The card itself, kept separate from the overlay so it can be laid out and
/// tested without a workspace behind it.
class IncomingCallCard extends StatelessWidget {
  const IncomingCallCard({
    required this.caller,
    required this.channelName,
    required this.onAccept,
    required this.onDecline,
    this.isBusy = false,
    super.key,
  });

  final Member? caller;

  /// Null when the channel is not in the workspace yet — a group DM the client
  /// has never opened still rings, and the card must not disappear over it.
  final String? channelName;
  final bool isBusy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final callerName = caller?.displayName ?? 'Someone';
    final subtitle = channelName == null
        ? 'Incoming call'
        : 'Incoming call · $channelName';
    return Semantics(
      liveRegion: true,
      label: '$callerName is calling',
      child: Material(
        key: const ValueKey('incoming-call-card'),
        color: context.surfaces.raised,
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: context.surfaces.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (caller != null)
                MemberAvatar(member: caller!, size: 40, showPresence: false)
              else
                Icon(Icons.call, size: 28, color: context.surfaces.muted),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      callerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                key: const ValueKey('incoming-call-decline'),
                onPressed: isBusy ? null : onDecline,
                tooltip: 'Decline',
                style: IconButton.styleFrom(
                  backgroundColor: FlucordColors.danger,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.call_end),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const ValueKey('incoming-call-accept'),
                onPressed: isBusy ? null : onAccept,
                tooltip: 'Accept',
                style: IconButton.styleFrom(
                  backgroundColor: FlucordColors.success,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.call),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
