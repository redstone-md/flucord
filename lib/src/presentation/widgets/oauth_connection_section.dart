import 'package:flutter/material.dart';

import '../../application/discord_account_connection_controller.dart';
import '../../domain/discord_oauth.dart';
import '../../theme/flucord_theme.dart';
import 'oauth_connected_account_directory.dart';
import 'remote_identity_image.dart';

class OAuthConnectionSection extends StatelessWidget {
  const OAuthConnectionSection({required this.controller, super.key});

  final DiscordAccountConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final account = controller.account;
    final linked = controller.oauthLinked;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Discord account',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'One account action coordinates your normal OAuth identity and the native Social SDK grant for approved friends and Direct Messages. Their credentials remain separate.',
            style: TextStyle(
              color: context.surfaces.muted,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _OAuthIdentityTile(controller: controller, account: account),
          if (linked && account != null) ...[
            const SizedBox(height: 16),
            OAuthConnectedAccountDirectory(connections: account.connections),
            const SizedBox(height: 16),
            _OAuthGuildDirectory(guilds: account.guilds),
          ],
        ],
      ),
    );
  }
}

class _OAuthIdentityTile extends StatelessWidget {
  const _OAuthIdentityTile({required this.controller, required this.account});

  final DiscordAccountConnectionController controller;
  final DiscordOAuthAccount? account;

  @override
  Widget build(BuildContext context) {
    final failed = controller.state == DiscordAccountConnectionState.failure;
    final statusColor = failed
        ? FlucordColors.danger
        : controller.isConnected
        ? FlucordColors.success
        : context.surfaces.muted;
    final status = _connectionStatus(controller, account);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        border: Border.all(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          _OAuthAvatar(account: account, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status,
              key: const ValueKey('discord-oauth-status'),
              style: TextStyle(
                color: failed ? FlucordColors.danger : null,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (controller.isFullyConnected)
            TextButton(
              key: const ValueKey('unlink-discord-account'),
              onPressed: controller.canDisconnect
                  ? controller.disconnect
                  : null,
              child: const Text('Disconnect'),
            )
          else ...[
            if (controller.isConnected)
              IconButton(
                key: const ValueKey('unlink-discord-account'),
                onPressed: controller.canDisconnect
                    ? controller.disconnect
                    : null,
                icon: const Icon(Icons.link_off_outlined, size: 17),
                tooltip: 'Disconnect Discord',
              ),
            FilledButton.icon(
              key: const ValueKey('link-discord-account'),
              onPressed: controller.canConnect ? controller.connect : null,
              icon: controller.isBusy
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_new, size: 16),
              label: Text(
                controller.isConnected ? 'Complete setup' : 'Connect Discord',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _connectionStatus(
  DiscordAccountConnectionController controller,
  DiscordOAuthAccount? account,
) => switch (controller.state) {
  DiscordAccountConnectionState.unavailable =>
    'Discord account authorization is unavailable in this build.',
  DiscordAccountConnectionState.disconnected => 'No Discord account connected.',
  DiscordAccountConnectionState.connecting =>
    'Waiting for Discord authorization…',
  DiscordAccountConnectionState.disconnecting =>
    'Disconnecting Discord account…',
  DiscordAccountConnectionState.failure =>
    controller.errorMessage ?? 'Discord account connection failed.',
  DiscordAccountConnectionState.partiallyConnected =>
    controller.needsSocial
        ? '${account?.displayName ?? 'Discord account'} · Complete native social authorization'
        : 'Native social access connected · Complete profile authorization',
  DiscordAccountConnectionState.connected =>
    controller.socialConnected
        ? '${account?.displayName ?? 'Discord account'} · ${account?.guildCount ?? 0} servers · Friends and DMs connected'
        : '${account?.displayName ?? 'Discord account'} · ${account?.guildCount ?? 0} servers',
};

class _OAuthAvatar extends StatelessWidget {
  const _OAuthAvatar({required this.account, required this.color});

  final DiscordOAuthAccount? account;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final account = this.account;
    return ClipOval(
      child: SizedBox.square(
        dimension: 28,
        child: RemoteIdentityImage(
          url: account?.avatarUrl,
          fallback: ColoredBox(
            color: context.surfaces.raised,
            child: Icon(
              account == null
                  ? Icons.person_outline
                  : Icons.verified_user_outlined,
              size: 18,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _OAuthGuildDirectory extends StatelessWidget {
  const _OAuthGuildDirectory({required this.guilds});

  final List<DiscordOAuthGuild> guilds;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'AUTHORIZED SERVERS · ${guilds.length}',
          style: TextStyle(
            color: context.surfaces.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        if (guilds.isEmpty)
          Text(
            'No servers were returned by the guilds scope.',
            style: TextStyle(color: context.surfaces.muted, fontSize: 11),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: context.surfaces.inset,
              border: Border.all(color: context.surfaces.border),
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 224),
              child: ListView.separated(
                key: const ValueKey('discord-oauth-guild-directory'),
                shrinkWrap: true,
                primary: false,
                padding: EdgeInsets.zero,
                itemCount: guilds.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: context.surfaces.border),
                itemBuilder: (context, index) =>
                    _OAuthGuildRow(guild: guilds[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _OAuthGuildRow extends StatelessWidget {
  const _OAuthGuildRow({required this.guild});

  final DiscordOAuthGuild guild;

  @override
  Widget build(BuildContext context) {
    final metadata = _metadata(guild);
    return Semantics(
      label: '${guild.name}, $metadata, messages unavailable through OAuth',
      child: Padding(
        key: ValueKey('discord-oauth-guild-${guild.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox.square(
                dimension: 32,
                child: RemoteIdentityImage(
                  url: guild.iconUrl,
                  fallback: ColoredBox(
                    color: context.surfaces.raised,
                    child: Center(
                      child: Text(
                        _initial(guild.name),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    guild.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metadata,
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
            const SizedBox(width: 8),
            Tooltip(
              message: 'OAuth does not grant message access',
              child: Icon(
                Icons.lock_outline,
                size: 15,
                color: context.surfaces.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _metadata(DiscordOAuthGuild guild) {
    final values = <String>[
      if (guild.isOwner)
        'Owner'
      else if (guild.isAdministrator)
        'Administrator',
      if (guild.approximateMemberCount case final count?) '$count members',
      if (guild.approximatePresenceCount case final count?) '$count online',
    ];
    return values.isEmpty ? 'Authorized server' : values.join(' · ');
  }

  static String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }
}
