import 'package:flutter/material.dart';

import '../../application/discord_social_sdk_controller.dart';
import '../../domain/discord_social_sdk.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'discord_account_connection_scope.dart';
import 'discord_social_sdk_scope.dart';

class DiscordSocialSdkStatusPanel extends StatelessWidget {
  const DiscordSocialSdkStatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = DiscordSocialSdkScope.of(context);
    final accountController = DiscordAccountConnectionScope.maybeOf(context);
    final presentation = _presentation(controller, context.surfaces);
    return Container(
      key: const ValueKey('discord-social-sdk-status'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        border: Border.all(color: context.surfaces.border),
        borderRadius: FlucordRadius.medium,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: _isBusy(controller.state)
                ? const CircularProgressIndicator(strokeWidth: 2)
                : FlucordIcon(
                    presentation.icon,
                    size: 17,
                    color: presentation.color,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presentation.title,
                  style: const TextStyle(
                    fontSize: FlucordType.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  presentation.detail,
                  style: TextStyle(
                    color: context.surfaces.muted,
                    fontSize: FlucordType.caption,
                    height: 1.35,
                  ),
                ),
                if (controller.state == DiscordSocialSdkControllerState.failure)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      key: const ValueKey('discord-social-sdk-retry'),
                      onPressed: controller.retry,
                      child: const Text('Retry'),
                    ),
                  ),
                if (controller.state ==
                    DiscordSocialSdkControllerState.signedOut)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton(
                      key: const ValueKey('discord-social-sdk-authorize'),
                      onPressed:
                          accountController?.connect ?? controller.authorize,
                      child: const Text('Connect Discord'),
                    ),
                  ),
                if (controller.state == DiscordSocialSdkControllerState.ready)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      key: const ValueKey('discord-social-sdk-disconnect'),
                      onPressed:
                          accountController?.disconnect ??
                          controller.disconnect,
                      child: const Text('Disconnect Discord'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static _StatusPresentation _presentation(
    DiscordSocialSdkController controller,
    FlucordSurfaceTheme surfaces,
  ) => switch (controller.state) {
    DiscordSocialSdkControllerState.idle ||
    DiscordSocialSdkControllerState.checking => _StatusPresentation(
      icon: FlucordIcons.syncing,
      color: surfaces.accentIcon,
      title: 'Checking native social access',
      detail: 'Inspecting the Discord Social SDK bridge.',
    ),
    DiscordSocialSdkControllerState.restoring => _StatusPresentation(
      icon: FlucordIcons.syncing,
      color: surfaces.accentIcon,
      title: 'Restoring native social session',
      detail:
          'Rotating the saved Social SDK grant and reconnecting to Discord.',
    ),
    DiscordSocialSdkControllerState.signedOut => _StatusPresentation(
      icon: FlucordIcons.credential,
      color: surfaces.warning,
      title: 'Native social account is disconnected',
      detail: 'The SDK is bundled. Connect Discord to enable live friends.',
    ),
    DiscordSocialSdkControllerState.authorizing => _StatusPresentation(
      icon: FlucordIcons.credential,
      color: surfaces.accentIcon,
      title: 'Waiting for Discord authorization',
      detail: 'Complete the native Discord authorization prompt.',
    ),
    DiscordSocialSdkControllerState.ready => _StatusPresentation(
      icon: FlucordIcons.friends,
      color: surfaces.success,
      title: 'Native social access is linked',
      detail:
          'The Social SDK session is authenticated and ready for live friend synchronization.',
    ),
    DiscordSocialSdkControllerState.unconfigured => _StatusPresentation(
      icon: FlucordIcons.settings,
      color: surfaces.warning,
      title: 'Discord application ID is missing',
      detail:
          'Build with FLUCORD_DISCORD_CLIENT_ID to enable Social SDK authorization.',
    ),
    DiscordSocialSdkControllerState.disconnecting => _StatusPresentation(
      icon: FlucordIcons.syncing,
      color: surfaces.accentIcon,
      title: 'Disconnecting native social session',
      detail: 'Closing the SDK connection and clearing its saved grant.',
    ),
    DiscordSocialSdkControllerState.unavailable => _unavailablePresentation(
      controller.availability,
      surfaces,
    ),
    DiscordSocialSdkControllerState.failure => _StatusPresentation(
      icon: FlucordIcons.error,
      color: surfaces.errorText,
      title: 'Native social access check failed',
      detail:
          'Flucord could not inspect the platform bridge. No Bot API fallback is used for friends.',
    ),
  };

  static bool _isBusy(DiscordSocialSdkControllerState state) => switch (state) {
    DiscordSocialSdkControllerState.checking ||
    DiscordSocialSdkControllerState.restoring ||
    DiscordSocialSdkControllerState.authorizing ||
    DiscordSocialSdkControllerState.disconnecting => true,
    _ => false,
  };

  static _StatusPresentation _unavailablePresentation(
    DiscordSocialSdkAvailability? availability,
    FlucordSurfaceTheme surfaces,
  ) {
    if (availability?.status ==
        DiscordSocialSdkAvailabilityStatus.unsupportedPlatform) {
      return _StatusPresentation(
        icon: FlucordIcons.desktop,
        color: surfaces.warning,
        title: 'Native social bridge is unavailable',
        detail:
            'This platform build has no Discord Social SDK bridge. Friends are not routed through Bot API.',
      );
    }
    return _StatusPresentation(
      icon: FlucordIcons.packageMissing,
      color: surfaces.warning,
      title: 'Discord Social SDK is not bundled',
      detail:
          'Link the approved Developer Portal SDK package to enable native relationship access. Friends are not routed through Bot API.',
    );
  }
}

final class _StatusPresentation {
  const _StatusPresentation({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final FlucordIconData icon;
  final Color color;
  final String title;
  final String detail;
}
