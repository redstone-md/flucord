import 'package:flutter/material.dart';

import '../../domain/chat_repository.dart';
import '../../theme/flucord_theme.dart';

/// The thin bar across the top of the workspace that says why nothing is
/// arriving. It takes no space while the session is connected.
///
/// [onRetry] is offered only when offline. While reconnecting the client is
/// already trying, and a press would only start the same thing over.
final class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    required this.status,
    required this.onRetry,
    super.key,
  });

  final RepositoryConnectionStatus status;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => switch (status) {
    RepositoryConnectionStatus.connected => const SizedBox.shrink(),
    // A session that cannot resume dials again from the start, so "connecting"
    // here is still the same outage as "reconnecting". The banner must not
    // blink off in between.
    RepositoryConnectionStatus.connecting ||
    RepositoryConnectionStatus.reconnecting => const _Bar(
      icon: Icons.sync,
      message: 'Connection lost. Reconnecting...',
      background: FlucordColors.warning,
      foreground: Colors.black,
    ),
    RepositoryConnectionStatus.offline => _Bar(
      icon: Icons.cloud_off,
      message: 'Not connected to Discord. New messages will not arrive.',
      background: FlucordColors.danger,
      foreground: Colors.white,
      onRetry: onRetry,
    ),
  };
}

final class _Bar extends StatelessWidget {
  const _Bar({
    required this.icon,
    required this.message,
    required this.background,
    required this.foreground,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final Color background;
  final Color foreground;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: ColoredBox(
        key: const ValueKey('connection-banner'),
        color: background,
        child: SizedBox(
          height: 28,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: foreground, fontSize: 12),
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  key: const ValueKey('connection-banner-retry'),
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: foreground,
                    minimumSize: const Size(0, 24),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
