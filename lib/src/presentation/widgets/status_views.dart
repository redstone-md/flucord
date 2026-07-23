import 'package:flutter/material.dart';

import '../../theme/flucord_theme.dart';

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
              style: TextStyle(color: context.surfaces.muted, fontSize: 12),
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
            const Icon(
              Icons.warning_amber,
              color: FlucordColors.copper,
              size: 30,
            ),
            const SizedBox(height: 12),
            const Text(
              'Workspace did not open',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'The transport returned an error.',
              style: TextStyle(color: context.surfaces.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class VoiceRoomView extends StatelessWidget {
  const VoiceRoomView({required this.channelName, super.key});

  final String channelName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq, size: 34, color: context.surfaces.muted),
          const SizedBox(height: 12),
          Text(
            channelName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            'Voice transport is the next tracer bullet.',
            style: TextStyle(color: context.surfaces.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
