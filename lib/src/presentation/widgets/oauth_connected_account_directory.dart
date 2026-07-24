import 'package:flutter/material.dart';

import '../../domain/discord_oauth.dart';
import '../../theme/flucord_theme.dart';

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
            style: TextStyle(
              color: context.surfaces.muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (connections.isEmpty)
          Text(
            'No third-party accounts were returned by the connections scope.',
            key: const ValueKey('discord-oauth-connections-empty'),
            style: TextStyle(color: context.surfaces.muted, fontSize: 11),
          )
        else
          Container(
            key: const ValueKey('discord-oauth-connection-directory'),
            decoration: BoxDecoration(
              color: context.surfaces.inset,
              border: Border.all(color: context.surfaces.border),
              borderRadius: BorderRadius.circular(6),
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
    final service = _serviceName(connection.type);
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
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
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
                  Text(
                    service,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    connection.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (connection.verified)
              const Tooltip(
                message: 'Verified connection',
                child: Icon(
                  Icons.verified_outlined,
                  size: 15,
                  color: FlucordColors.success,
                ),
              ),
            if (connection.isPublic) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Visible on Discord profile',
                child: Icon(
                  Icons.visibility_outlined,
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

String _serviceName(String type) => switch (type) {
  'battlenet' => 'Battle.net',
  'epicgames' => 'Epic Games',
  'playstation' => 'PlayStation Network',
  'riotgames' => 'Riot Games',
  'twitter' => 'X / Twitter',
  'youtube' => 'YouTube',
  _ =>
    type
        .split(RegExp(r'[_-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' '),
};

IconData _serviceIcon(String type) => switch (type) {
  'spotify' => Icons.graphic_eq,
  'steam' ||
  'playstation' ||
  'xbox' ||
  'epicgames' ||
  'riotgames' => Icons.sports_esports_outlined,
  'github' => Icons.code,
  'youtube' || 'twitch' || 'tiktok' => Icons.play_circle_outline,
  'paypal' => Icons.payments_outlined,
  'domain' => Icons.language,
  _ => Icons.link,
};
