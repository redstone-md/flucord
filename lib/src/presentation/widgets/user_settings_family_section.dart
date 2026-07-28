import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/family_centre_controller.dart';
import '../../domain/family_centre.dart';
import '../../theme/flucord_theme.dart';
import 'user_settings_controls.dart';

/// The family centre: who is linked to this account, and what Discord reports
/// about a linked teenager.
///
/// Counts only, because counts are all Discord's family centre reports. No
/// message content, no call audio, nothing about what was said — and this page
/// does not go looking for more than the summary offers.
class FamilyCentreSection extends StatefulWidget {
  const FamilyCentreSection({required this.controller, super.key});

  final FamilyCentreController controller;

  @override
  State<FamilyCentreSection> createState() => _FamilyCentreSectionState();
}

class _FamilyCentreSectionState extends State<FamilyCentreSection> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  void dispose() {
    // A link code lets a parent see this account; leaving one in memory for
    // the next person to open settings would be leaving a credential out.
    widget.controller.forgetLinkCode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final family = controller.familyCentre;
      return Column(
        key: const ValueKey('settings-section-family'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionHeader(
            title: 'Family Center',
            subtitle: 'Who is linked to this account, and what is reported.',
          ),
          if (controller.isLoading && family == null)
            const Padding(
              key: ValueKey('family-loading'),
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.error != null && family == null)
            _FamilyError(
              onRetry: () => unawaited(controller.load(refresh: true)),
            )
          else if (family != null)
            ..._body(context, controller, family),
        ],
      );
    },
  );

  List<Widget> _body(
    BuildContext context,
    FamilyCentreController controller,
    FamilyCentre family,
  ) => [
    if (family.ageGroup.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          // Discord's own bucket, verbatim: renaming it would be answering a
          // legal question this client has no standing to answer.
          'Age group: ${family.ageGroup}',
          key: const ValueKey('family-age-group'),
          style: TextStyle(fontSize: 12, color: context.surfaces.muted),
        ),
      ),
    if (!family.hasLinkedUsers)
      const Padding(
        key: ValueKey('family-none-linked'),
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No accounts are linked to this one.'),
      )
    else ...[
      Text('Linked accounts', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      for (final userId in family.linkedUserIds)
        Container(
          key: ValueKey('family-linked-$userId'),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: context.surfaces.raised,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(family.nameFor(userId)),
        ),
    ],
    if (family.activity case final activity? when !activity.isEmpty)
      _ActivitySummary(activity: activity, family: family),
    const SizedBox(height: 16),
    _LinkCode(controller: controller),
  ];
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({required this.activity, required this.family});

  final TeenActivitySummary activity;
  final FamilyCentre family;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('family-activity'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      Text('Activity', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
        // Said plainly, because a parent reading this should not have to
        // guess whether Flucord is showing them somebody's messages.
        'Counts only. Discord reports how much, never what was said.',
        style: TextStyle(fontSize: 12, color: context.surfaces.muted),
      ),
      const SizedBox(height: 8),
      for (final entry in activity.totals.entries)
        Padding(
          key: ValueKey('family-total-${entry.key}'),
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('${entry.key}: ${entry.value}'),
        ),
      if (activity.userIds.isNotEmpty)
        Padding(
          key: const ValueKey('family-activity-people'),
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'People: ${activity.userIds.map(family.nameFor).join(', ')}',
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
          ),
        ),
      if (activity.guildIds.isNotEmpty)
        Padding(
          key: const ValueKey('family-activity-servers'),
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${activity.guildIds.length} server'
            '${activity.guildIds.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
          ),
        ),
    ],
  );
}

class _LinkCode extends StatelessWidget {
  const _LinkCode({required this.controller});

  final FamilyCentreController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.linkCode case final code?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            code,
            key: const ValueKey('family-link-code'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'A parent enters this to link to your account. It is forgotten '
            'when this page closes.',
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.wasLinkCodeRefused)
          Padding(
            key: const ValueKey('family-link-refused'),
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Discord will not issue a code for this account.',
              style: TextStyle(fontSize: 12, color: context.surfaces.muted),
            ),
          ),
        FilledButton.tonal(
          key: const ValueKey('family-request-code'),
          onPressed: controller.isRequestingLinkCode
              ? null
              : () => unawaited(controller.requestLinkCode()),
          child: const Text('Get a link code'),
        ),
      ],
    );
  }
}

class _FamilyError extends StatelessWidget {
  const _FamilyError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('family-error'),
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Discord did not answer about this account.'),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('family-retry'),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    ),
  );
}
