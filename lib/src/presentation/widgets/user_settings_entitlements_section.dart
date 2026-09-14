import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/account_entitlements_controller.dart';
import '../../domain/user_settings.dart';
import '../../theme/flucord_theme.dart';
import 'user_settings_controls.dart';

/// What the account holds: its Nitro tier, its boosts, and what those change.
///
/// Read-only, and the page says so. Buying, gifting, and boosting are
/// Discord's commerce, and an independent client has no part in them: what
/// it can do honestly is show what the account already has.
class EntitlementsSettingsSection extends StatefulWidget {
  const EntitlementsSettingsSection({required this.controller, super.key});

  final AccountEntitlementsController controller;

  @override
  State<EntitlementsSettingsSection> createState() =>
      _EntitlementsSettingsSectionState();
}

class _EntitlementsSettingsSectionState
    extends State<EntitlementsSettingsSection> {
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
      final entitlements = controller.entitlements;
      return Column(
        key: const ValueKey('settings-section-entitlements'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionHeader(
            title: 'Entitlements',
            subtitle: 'What this account holds, and what it changes.',
          ),
          Text(
            'This page only reports what Discord has already granted. '
            'Flucord cannot buy, gift, or cancel anything.',
            key: const ValueKey('entitlements-disclaimer'),
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
          ),
          const SizedBox(height: 12),
          if (controller.isLoading && entitlements == null)
            const Padding(
              key: ValueKey('entitlements-loading'),
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.error != null && entitlements == null)
            _EntitlementsError(
              onRetry: () => unawaited(controller.load(refresh: true)),
            )
          else if (entitlements != null) ...[
            // Stated as a value, never a control: a switch here could not
            // change anything, and a button that always fails would read as
            // a purchase button that is broken.
            SettingRow(
              title: 'Nitro tier',
              description: 'What Discord has granted this account.',
              support: UserSettingSupport.accountOnly,
              child: SettingValue(entitlements.premiumTier.label),
            ),
            if (entitlements.boostsHeld > 0)
              Padding(
                key: const ValueKey('entitlements-boosts'),
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${entitlements.boostsHeld} server boost'
                  '${entitlements.boostsHeld == 1 ? '' : 's'} held.',
                  style: TextStyle(fontSize: 12, color: context.surfaces.muted),
                ),
              ),
            if (entitlements.premiumPerks.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'What it changes',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final perk in entitlements.premiumPerks)
                Padding(
                  key: ValueKey('entitlements-perk-${perk.hashCode}'),
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    perk,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.surfaces.muted,
                    ),
                  ),
                ),
            ],
            if (entitlements.entitlements.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Held grants',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              for (final grant in entitlements.entitlements)
                Container(
                  key: ValueKey('entitlement-${grant.id}'),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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
                              grant.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              grant.describeExpiry(),
                              style: TextStyle(
                                fontSize: 11,
                                color: context.surfaces.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (entitlements.hasNothing)
              const Padding(
                key: ValueKey('entitlements-none'),
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'This account holds nothing Discord granted specially.',
                ),
              ),
          ],
        ],
      );
    },
  );
}

class _EntitlementsError extends StatelessWidget {
  const _EntitlementsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('entitlements-error'),
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Discord did not return what this account holds.'),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('entitlements-retry'),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    ),
  );
}
