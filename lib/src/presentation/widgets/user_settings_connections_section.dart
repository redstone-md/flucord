import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/account_connections_controller.dart';
import '../../domain/account_connections.dart';
import '../../theme/flucord_theme.dart';
import 'user_settings_controls.dart';

/// The account's third-party connections: what is linked, what can be.
///
/// Linking opens the service's own page in the system browser, and the page
/// says so before anything else: the credentials being exchanged belong to
/// the person and the service, and none of them pass through Flucord.
class ConnectionsSettingsSection extends StatefulWidget {
  const ConnectionsSettingsSection({required this.controller, super.key});

  final AccountConnectionsController controller;

  @override
  State<ConnectionsSettingsSection> createState() =>
      _ConnectionsSettingsSectionState();
}

class _ConnectionsSettingsSectionState
    extends State<ConnectionsSettingsSection> {
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
        key: const ValueKey('settings-section-connections'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionHeader(
            title: 'Connections',
            subtitle:
                'Third-party accounts linked to this one, and what can be '
                'linked.',
          ),
          Text(
            'A link opens the service\'s own page in your browser. '
            'Flucord never sees the sign-in you do there.',
            key: const ValueKey('connections-disclaimer'),
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
          ),
          const SizedBox(height: 12),
          if (controller.isLoading && controller.connections.isEmpty)
            const Padding(
              key: ValueKey('connections-loading'),
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.error != null && controller.connections.isEmpty)
            _ConnectionsError(
              onRetry: () => unawaited(controller.load(refresh: true)),
            )
          else ...[
            if (controller.refusedService case final refused?)
              Padding(
                key: const ValueKey('connections-link-refused'),
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Discord will not start a $refused link for this account.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (controller.unlinkRefusal case final refused?)
              Padding(
                key: const ValueKey('connections-unlink-refused'),
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Discord refused to remove $refused. It may already be '
                  'gone.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (controller.connections.isEmpty)
              const Padding(
                key: ValueKey('connections-none'),
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No third-party accounts are linked.'),
              )
            else ...[
              for (final connection in controller.connections)
                _ConnectionRow(connection: connection, controller: controller),
              const SizedBox(height: 6),
            ],
            TextButton(
              key: const ValueKey('connections-refresh'),
              onPressed: controller.isLoading
                  ? null
                  : () => unawaited(controller.load(refresh: true)),
              child: const Text('Refresh'),
            ),
            const SizedBox(height: 8),
            _LinkButtons(controller: controller),
          ],
        ],
      );
    },
  );
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.connection, required this.controller});

  final AccountConnection connection;
  final AccountConnectionsController controller;

  @override
  Widget build(BuildContext context) {
    final service = connection.serviceName;
    final status = <String>[
      if (connection.verified) 'Verified',
      if (connection.isPublic) 'Visible on your profile',
      if (connection.showActivity) 'Shows activity',
      if (connection.revoked) 'Access was revoked by $service',
    ];
    return Container(
      key: ValueKey('connection-${connection.type}-${connection.id}'),
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
                Text(
                  service,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                Text(
                  connection.name,
                  style: TextStyle(fontSize: 12, color: context.surfaces.muted),
                ),
                if (status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      status.join(' · '),
                      key: ValueKey('connection-status-${connection.type}'),
                      style: TextStyle(
                        fontSize: 11,
                        color: connection.revoked
                            ? Theme.of(context).colorScheme.error
                            : context.surfaces.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            key: ValueKey('connection-unlink-${connection.type}'),
            onPressed: controller.isUnlinking
                ? null
                : () => unawaited(controller.unlink(connection)),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
  }
}

/// The services a link can start from. Discord decides per account which of
/// these it will actually offer, so a tap the service refuses is answered on
/// the page by name rather than being hidden from the list.
class _LinkButtons extends StatelessWidget {
  const _LinkButtons({required this.controller});

  final AccountConnectionsController controller;

  static const _services = [
    ('spotify', 'Spotify'),
    ('steam', 'Steam'),
    ('github', 'GitHub'),
    ('twitch', 'Twitch'),
    ('youtube', 'YouTube'),
    ('tiktok', 'TikTok'),
    ('reddit', 'Reddit'),
    ('paypal', 'PayPal'),
    ('epicgames', 'Epic Games'),
    ('playstation', 'PlayStation'),
    ('xbox', 'Xbox'),
    ('riotgames', 'Riot Games'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('connections-link-services'),
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (type, label) in _services)
          ActionChip(
            key: ValueKey('connection-link-$type'),
            label: Text(label, style: const TextStyle(fontSize: 11)),
            onPressed: controller.isLinking
                ? null
                : () => unawaited(controller.startLink(type)),
          ),
      ],
    );
  }
}

class _ConnectionsError extends StatelessWidget {
  const _ConnectionsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('connections-error'),
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Discord did not return your connections.'),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('connections-retry'),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    ),
  );
}
