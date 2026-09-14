import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/auth_session_controller.dart';
import '../../domain/auth_session.dart';
import '../../theme/flucord_theme.dart';
import 'user_settings_controls.dart';

/// Every device signed in to this account, and the way to sign one out.
class DevicesSettingsSection extends StatefulWidget {
  const DevicesSettingsSection({required this.controller, super.key});

  final AuthSessionController controller;

  @override
  State<DevicesSettingsSection> createState() => _DevicesSettingsSectionState();
}

class _DevicesSettingsSectionState extends State<DevicesSettingsSection> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return Column(
        key: const ValueKey('settings-section-devices'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionHeader(
            title: 'Devices',
            subtitle: 'Everywhere this account is signed in.',
          ),
          if (controller.isLoading && controller.sessions.isEmpty)
            const Padding(
              key: ValueKey('devices-loading'),
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.error != null && controller.sessions.isEmpty)
            _DevicesError(
              onRetry: () => unawaited(controller.load(refresh: true)),
            )
          else ...[
            if (controller.wasEndRefused)
              Padding(
                key: const ValueKey('devices-refused'),
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Discord would not end that session. It asks for the '
                  'account password first, which Flucord does not hold.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            for (final session in controller.sessions)
              _SessionRow(session: session, controller: controller),
            if (controller.sessions.isEmpty)
              const Padding(
                key: ValueKey('devices-empty'),
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Discord listed no other sessions.'),
              ),
            const SizedBox(height: 12),
            if (controller.otherSessions.isNotEmpty)
              FilledButton.tonal(
                key: const ValueKey('devices-end-others'),
                onPressed: controller.isEnding
                    ? null
                    : () => unawaited(_confirmEndOthers(context, controller)),
                child: const Text('Sign out everywhere else'),
              ),
          ],
        ],
      );
    },
  );

  Future<void> _confirmEndOthers(
    BuildContext context,
    AuthSessionController controller,
  ) async {
    // Signing another device out cannot be undone from here, so it asks
    // first — the same reason blocking somebody does.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('devices-confirm'),
        title: const Text('Sign out everywhere else?'),
        content: Text(
          '${controller.otherSessions.length} other session'
          '${controller.otherSessions.length == 1 ? '' : 's'} will be ended. '
          'This one stays signed in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('devices-confirm-accept'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await controller.endOtherSessions();
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.controller});

  final AuthSession session;
  final AuthSessionController controller;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('device-${session.idHash}'),
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.surfaces.raised,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    session.deviceLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (session.isCurrent) ...[
                    const SizedBox(width: 8),
                    Text(
                      'This device',
                      key: ValueKey('device-current-${session.idHash}'),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.surfaces.muted,
                      ),
                    ),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _describe(session),
                  style: TextStyle(fontSize: 12, color: context.surfaces.muted),
                ),
              ),
            ],
          ),
        ),
        // The current session has no end control: ending it is signing out,
        // which is a different thing in a different place.
        if (!session.isCurrent)
          TextButton(
            key: ValueKey('device-end-${session.idHash}'),
            onPressed: controller.isEnding
                ? null
                : () => unawaited(controller.endSession(session.idHash)),
            child: const Text('Sign out'),
          ),
      ],
    ),
  );

  static String _describe(AuthSession session) {
    final parts = <String>[
      if (session.location.isNotEmpty) session.location,
      if (session.ipAddress.isNotEmpty) session.ipAddress,
      if (session.lastUsedAt case final seen?) 'last used ${_when(seen)}',
    ];
    return parts.isEmpty ? 'Discord gave no details' : parts.join(' · ');
  }

  /// Discord rounds the time it reports, so this never claims a precise one.
  static String _when(DateTime seen) =>
      '${seen.year}-${_two(seen.month)}-${_two(seen.day)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _DevicesError extends StatelessWidget {
  const _DevicesError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('devices-error'),
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Discord did not list this account\'s sessions.'),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('devices-retry'),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    ),
  );
}
