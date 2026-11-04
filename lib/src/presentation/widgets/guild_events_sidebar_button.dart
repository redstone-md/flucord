import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

class GuildEventsSidebarButton extends StatelessWidget {
  const GuildEventsSidebarButton({
    required this.count,
    required this.isLoading,
    required this.hasError,
    required this.onPressed,
    super.key,
  });

  final int count;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: const ValueKey('guild-events-button'),
      onTap: onPressed,
      borderRadius: FlucordRadius.small,
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              FlucordIcon(
                hasError ? FlucordIcons.eventUnavailable : FlucordIcons.event,
                size: 19,
                color: hasError ? context.surfaces.warning : null,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Events',
                  style: TextStyle(
                    fontSize: FlucordType.label,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (isLoading)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (count > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: context.surfaces.raised,
                    borderRadius: FlucordRadius.small,
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: FlucordType.caption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
