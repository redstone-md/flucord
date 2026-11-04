import 'package:flutter/material.dart';

import '../../domain/account_connections.dart';
import '../../domain/discord_oauth.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

class OAuthConnectedAccountDirectory extends StatelessWidget {
  const OAuthConnectedAccountDirectory({
    required this.connections,
    this.showHeader = true,
    super.key,
  });

  final List<DiscordOAuthConnection> connections;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          Text(
            'CONNECTED ACCOUNTS · ${connections.length}',
            style: FlucordTextRole.caption.strong.copyWith(
              color: context.surfaces.muted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (connections.isEmpty)
          Text(
            'No third-party accounts were returned by the connections scope.',
            key: const ValueKey('discord-oauth-connections-empty'),
            style: TextStyle(
              color: context.surfaces.muted,
              fontSize: FlucordType.caption,
            ),
          )
        else
          Container(
            key: const ValueKey('discord-oauth-connection-directory'),
            decoration: BoxDecoration(
              color: context.surfaces.inset,
              border: Border.all(color: context.surfaces.border),
              borderRadius: FlucordRadius.medium,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < connections.length; index++) ...[
                  if (index > 0)
                    Divider(height: 1, color: context.surfaces.border),
                  _ConnectedAccountRow(connection: connections[index]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ConnectedAccountRow extends StatelessWidget {
  const _ConnectedAccountRow({required this.connection});

  final DiscordOAuthConnection connection;

  @override
  Widget build(BuildContext context) {
    final service = ConnectionService.nameOf(connection.type);
    final status = <String>[
      if (connection.verified) 'Verified',
      if (connection.isPublic) 'Visible',
      if (connection.showActivity) 'Activity',
      if (connection.revoked) 'Revoked',
    ];
    return Semantics(
      label: '$service, ${connection.name}, ${status.join(', ')}',
      child: Padding(
        key: ValueKey(
          'discord-oauth-connection-${connection.type}-${connection.id}',
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: context.surfaces.raised,
                borderRadius: FlucordRadius.medium,
              ),
              child: FlucordIcon(
                _serviceIcon(connection.type),
                size: 17,
                color: connection.revoked
                    ? context.surfaces.muted
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service, style: FlucordTextRole.caption.strong),
                  const SizedBox(height: 1),
                  Text(
                    connection.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: FlucordType.caption,
                    ),
                  ),
                ],
              ),
            ),
            if (connection.verified)
              Tooltip(
                message: 'Verified connection',
                child: FlucordIcon(
                  FlucordIcons.verified,
                  size: 15,
                  color: context.surfaces.success,
                ),
              ),
            if (connection.isPublic) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Visible on Discord profile',
                child: FlucordIcon(
                  FlucordIcons.visible,
                  size: 15,
                  color: context.surfaces.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

FlucordIconData _serviceIcon(String type) => switch (type) {
  'spotify' => FlucordIcons.music,
  'steam' ||
  'playstation' ||
  'xbox' ||
  'epicgames' ||
  'riotgames' => FlucordIcons.game,
  'github' => FlucordIcons.code,
  'youtube' || 'twitch' || 'tiktok' => FlucordIcons.streaming,
  'paypal' => FlucordIcons.payment,
  'domain' => FlucordIcons.website,
  _ => FlucordIcons.link,
};
