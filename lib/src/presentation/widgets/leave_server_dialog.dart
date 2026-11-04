import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'destructive_confirmation.dart';
import 'rail_tile.dart';
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

/// The server being left: its 40 px tile, its name, and a caption with its
/// member count and the day the user joined, as far as they are known.
class _LeftServerCard extends StatelessWidget {
  const _LeftServerCard({required this.space});

  static const _tileSize = 40.0;

  final CommunitySpace space;

  String? _caption(MaterialLocalizations localizations) {
    final count = space.memberCount;
    final joined = space.joinedAt?.toLocal();
    final parts = [
      if (count != null)
        '${localizations.formatDecimal(count)} '
            '${count == 1 ? 'member' : 'members'}',
      if (joined != null)
        'Joined ${localizations.formatShortMonthDay(joined)}, '
            '${localizations.formatYear(joined)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final caption = _caption(MaterialLocalizations.of(context));
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
                  fallback: RailMonogram(space.monogram),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  space.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FlucordTextRole.heading.style.copyWith(
                    color: surfaces.text,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FlucordTextRole.caption.style.copyWith(
                      color: surfaces.captionText,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
