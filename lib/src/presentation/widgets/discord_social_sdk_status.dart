import 'package:flutter/material.dart';

import '../../application/discord_social_sdk_controller.dart';
import '../../domain/discord_social_sdk.dart';
import '../../theme/flucord_theme.dart';
import 'discord_social_sdk_scope.dart';

class DiscordSocialSdkStatusPanel extends StatelessWidget {
  const DiscordSocialSdkStatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = DiscordSocialSdkScope.of(context);
    final presentation = _presentation(controller);
    return Container(
      key: const ValueKey('discord-social-sdk-status'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        border: Border.all(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: _isBusy(controller.state)
                ? const CircularProgressIndicator(strokeWidth: 2)
                : Icon(presentation.icon, size: 17, color: presentation.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presentation.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  presentation.detail,
                  style: TextStyle(
                    color: context.surfaces.muted,
                    fontSize: 11,
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
                      onPressed: controller.authorize,
                      child: const Text('Connect Discord'),
                    ),
                  ),
                if (controller.state == DiscordSocialSdkControllerState.ready)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      key: const ValueKey('discord-social-sdk-disconnect'),
                      onPressed: controller.disconnect,
                      child: const Text('Disconnect social session'),
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
  ) => switch (controller.state) {
    DiscordSocialSdkControllerState.idle ||
    DiscordSocialSdkControllerState.checking => const _StatusPresentation(
      icon: Icons.sync,
      color: FlucordColors.brand,
      title: 'Checking native social access',
      detail: 'Inspecting the Discord Social SDK bridge.',
    ),
    DiscordSocialSdkControllerState.restoring => const _StatusPresentation(
      icon: Icons.sync,
      color: FlucordColors.brand,
      title: 'Restoring native social session',
      detail:
          'Rotating the saved Social SDK grant and reconnecting to Discord.',
    ),
    DiscordSocialSdkControllerState.signedOut => const _StatusPresentation(
      icon: Icons.key_outlined,
      color: FlucordColors.warning,
      title: 'Native social account is disconnected',
      detail: 'The SDK is bundled. Connect Discord to enable live friends.',
    ),
    DiscordSocialSdkControllerState.authorizing => const _StatusPresentation(
      icon: Icons.key_outlined,
      color: FlucordColors.brand,
      title: 'Waiting for Discord authorization',
      detail: 'Complete the native Discord authorization prompt.',
    ),
    DiscordSocialSdkControllerState.ready => const _StatusPresentation(
      icon: Icons.people_outline,
      color: FlucordColors.success,
      title: 'Native social access is linked',
      detail:
          'The Social SDK session is authenticated and ready for live friend synchronization.',
    ),
    DiscordSocialSdkControllerState.unconfigured => const _StatusPresentation(
      icon: Icons.settings_outlined,
      color: FlucordColors.warning,
      title: 'Discord application ID is missing',
      detail:
          'Build with FLUCORD_DISCORD_CLIENT_ID to enable Social SDK authorization.',
    ),
    DiscordSocialSdkControllerState.disconnecting => const _StatusPresentation(
      icon: Icons.sync,
      color: FlucordColors.brand,
      title: 'Disconnecting native social session',
      detail: 'Closing the SDK connection and clearing its saved grant.',
    ),
    DiscordSocialSdkControllerState.unavailable => _unavailablePresentation(
      controller.availability,
    ),
    DiscordSocialSdkControllerState.failure => const _StatusPresentation(
      icon: Icons.error_outline,
      color: FlucordColors.danger,
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
  ) {
    if (availability?.status ==
        DiscordSocialSdkAvailabilityStatus.unsupportedPlatform) {
      return const _StatusPresentation(
        icon: Icons.desktop_windows_outlined,
        color: FlucordColors.warning,
        title: 'Native social bridge is unavailable',
        detail:
            'This platform build has no Discord Social SDK bridge. Friends are not routed through Bot API.',
      );
    }
    return const _StatusPresentation(
      icon: Icons.extension_off_outlined,
      color: FlucordColors.warning,
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

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
}
