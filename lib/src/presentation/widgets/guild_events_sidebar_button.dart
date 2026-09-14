import 'package:flutter/material.dart';

import '../../theme/flucord_theme.dart';

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
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(
                hasError ? Icons.event_busy_outlined : Icons.event_outlined,
                size: 19,
                color: hasError ? FlucordColors.warning : null,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Events',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
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
