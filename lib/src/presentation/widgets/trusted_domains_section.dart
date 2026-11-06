import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/trusted_domains_controller.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_button.dart';
import 'user_settings_controls.dart';

/// The sites trusted from the "Leaving" dialog, and a way to forget them.
class TrustedDomainsSection extends StatelessWidget {
  const TrustedDomainsSection({required this.controller, super.key});

  final TrustedDomainsController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final surfaces = context.surfaces;
      final hosts = [...controller.hosts]..sort();
      final caption = FlucordTextRole.caption.style.copyWith(
        color: surfaces.muted,
      );
      return Column(
        key: const ValueKey('trusted-domains-section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionHeader(
            title: 'Trusted sites',
            subtitle:
                'Links to these sites open without asking first. Links to '
                'Discord never ask.',
          ),
          const SizedBox(height: 8),
          if (hosts.isEmpty)
            Text('No sites are trusted.', style: caption)
          else ...[
            for (final host in hosts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  host,
                  style: FlucordTextRole.body.style.copyWith(
                    color: surfaces.bodyText,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            FlucordButton(
              key: const ValueKey('trusted-domains-clear'),
              label: 'Clear trusted sites',
              onPressed: () => unawaited(controller.clear()),
            ),
          ],
          if (controller.writeError != null) ...[
            const SizedBox(height: 8),
            Text(
              'The list could not be saved.',
              style: FlucordTextRole.caption.style.copyWith(
                color: surfaces.errorText,
              ),
            ),
          ],
        ],
      );
    },
  );
}
