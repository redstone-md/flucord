import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

class LoadingWorkspaceView extends StatelessWidget {
  const LoadingWorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 14),
            Text(
              'Opening workspace',
              style: TextStyle(
                color: context.surfaces.muted,
                fontSize: FlucordType.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FailedWorkspaceView extends StatelessWidget {
  const FailedWorkspaceView({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlucordIcon(
              FlucordIcons.warning,
              color: context.surfaces.warning,
              size: 30,
            ),
            const SizedBox(height: 12),
            Text('Workspace did not open', style: FlucordTextRole.label.strong),
            const SizedBox(height: 4),
            Text(
              'Your servers and messages could not be loaded.',
              style: TextStyle(
                color: context.surfaces.muted,
                fontSize: FlucordType.caption,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const FlucordIcon(FlucordIcons.refresh, size: 17),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class ChannelLoadingView extends StatelessWidget {
  const ChannelLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class ChannelFailureView extends StatelessWidget {
  const ChannelFailureView({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlucordIcon(
            FlucordIcons.offline,
            color: context.surfaces.warning,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            'Message history unavailable',
            style: FlucordTextRole.label.strong,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const FlucordIcon(FlucordIcons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class EmptyWorkspaceView extends StatelessWidget {
  const EmptyWorkspaceView({required this.onOpenConnections, super.key});

  final VoidCallback onOpenConnections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlucordIcon(
              FlucordIcons.server,
              size: 30,
              color: context.surfaces.muted,
            ),
            const SizedBox(height: 12),
            Text('No accessible servers', style: FlucordTextRole.label.strong),
            const SizedBox(height: 5),
            Text(
              'Install the bot in a server with channel access.',
              style: TextStyle(
                color: context.surfaces.muted,
                fontSize: FlucordType.caption,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onOpenConnections,
              icon: const FlucordIcon(FlucordIcons.link, size: 16),
              label: const Text('Connections'),
            ),
          ],
        ),
      ),
    );
  }
}
