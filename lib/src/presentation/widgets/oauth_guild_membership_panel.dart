import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/oauth_guild_membership_controller.dart';
import '../../domain/discord_oauth.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';

class OAuthGuildMembershipPanel extends StatefulWidget {
  const OAuthGuildMembershipPanel({
    required this.controller,
    required this.account,
    required this.guild,
    super.key,
  });

  final OAuthGuildMembershipController controller;
  final DiscordOAuthAccount account;
  final DiscordOAuthGuild guild;

  @override
  State<OAuthGuildMembershipPanel> createState() =>
      _OAuthGuildMembershipPanelState();
}

class _OAuthGuildMembershipPanelState extends State<OAuthGuildMembershipPanel> {
  @override
  void initState() {
    super.initState();
    _queueLoad();
  }

  @override
  void didUpdateWidget(covariant OAuthGuildMembershipPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.account.id != widget.account.id ||
        oldWidget.guild.id != widget.guild.id) {
      _queueLoad();
    }
  }

  void _queueLoad() {
    final guildId = widget.guild.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.guild.id == guildId) {
        unawaited(widget.controller.load(guildId));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final snapshot = widget.controller.snapshotFor(widget.guild.id);
        return Container(
          key: ValueKey('oauth-guild-membership-${widget.guild.id}'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.surfaces.inset,
            border: Border.all(color: context.surfaces.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: switch (snapshot.state) {
            OAuthGuildMembershipLoadState.idle ||
            OAuthGuildMembershipLoadState.loading => _LoadingMembership(
              account: widget.account,
            ),
            OAuthGuildMembershipLoadState.ready => _LoadedMembership(
              account: widget.account,
              membership: snapshot.membership!,
            ),
            OAuthGuildMembershipLoadState.failure => _FailedMembership(
              message: snapshot.errorMessage!,
              onRetry: () => widget.controller.retry(widget.guild.id),
            ),
          },
        );
      },
    );
  }
}

class _LoadingMembership extends StatelessWidget {
  const _LoadingMembership({required this.account});

  final DiscordOAuthAccount account;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MembershipAvatar(account: account),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Loading server profile…',
            style: TextStyle(fontSize: 11),
          ),
        ),
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    );
  }
}

class _LoadedMembership extends StatelessWidget {
  const _LoadedMembership({required this.account, required this.membership});

  final DiscordOAuthAccount account;
  final DiscordOAuthGuildMembership membership;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (membership.joinedAt case final joinedAt?) 'Joined ${_date(joinedAt)}',
      '${membership.roleCount} ${membership.roleCount == 1 ? 'role' : 'roles'}',
      if (membership.premiumSince != null) 'Server booster',
      if (membership.pending) 'Screening pending',
      if (membership.communicationDisabledUntil case final timeout?)
        'Timed out until ${_date(timeout)}',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MembershipAvatar(account: account, avatarUrl: membership.avatarUrl),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                membership.nickname ?? account.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              for (final detail in details)
                Text(
                  detail,
                  style: TextStyle(
                    color: context.surfaces.muted,
                    fontSize: 9,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

class _FailedMembership extends StatelessWidget {
  const _FailedMembership({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          key: const ValueKey('oauth-guild-membership-error'),
          style: TextStyle(color: context.surfaces.muted, fontSize: 10),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

class _MembershipAvatar extends StatelessWidget {
  const _MembershipAvatar({required this.account, this.avatarUrl});

  final DiscordOAuthAccount account;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox.square(
        dimension: 30,
        child: RemoteIdentityImage(
          url: avatarUrl ?? account.avatarUrl,
          fallback: ColoredBox(
            color: context.surfaces.raised,
            child: const Icon(Icons.person_outline, size: 16),
          ),
        ),
      ),
    );
  }
}
