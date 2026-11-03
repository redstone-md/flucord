import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'destructive_confirmation.dart';
import 'remote_identity_image.dart';

/// Asks before leaving a server.
///
/// Leaving is not undoable from any surface Flucord has, so the ask names
/// the server, shows it in a card, and says what disappears with it. Answers
/// whether the user confirmed.
Future<bool> showLeaveServerConfirmation(
  BuildContext context, {
  required CommunitySpace space,
}) => confirmDestructiveAction(
  context,
  title: 'Leave ${space.name}?',
  message:
      'You will not see this server or its messages until you are invited '
      'back.',
  confirmLabel: 'Leave',
  detail: _LeftServerCard(space: space),
  dialogKey: const ValueKey('leave-server-dialog'),
  confirmKey: const ValueKey('leave-server-confirm'),
);

/// The server being left: its 40 px tile and its name, on a recessed card.
class _LeftServerCard extends StatelessWidget {
  const _LeftServerCard({required this.space});

  static const _tileSize = 40.0;

  final CommunitySpace space;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Container(
      key: const ValueKey('leave-server-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaces.inset,
        borderRadius: FlucordRadius.medium,
        border: Border.all(color: surfaces.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: FlucordRadius.medium,
            child: SizedBox.square(
              dimension: _tileSize,
              child: ColoredBox(
                color: Color(space.colorValue),
                child: RemoteIdentityImage(
                  url: space.iconUrl,
                  fallback: Center(
                    child: Text(
                      space.monogram,
                      style: FlucordTextRole.label.style.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              space.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FlucordTextRole.heading.style.copyWith(
                color: surfaces.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
