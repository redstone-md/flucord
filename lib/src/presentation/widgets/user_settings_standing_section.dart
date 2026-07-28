import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/account_standing_controller.dart';
import '../../domain/account_standing.dart';
import '../../theme/flucord_theme.dart';
import 'user_settings_controls.dart';

/// What Discord has on record against the account, and the one thing that can
/// be done about it: ask for a record to be looked at again.
///
/// Nothing here interprets Discord's numeric state. The bundle ships no enum
/// for it that static analysis recovers, and telling somebody their account is
/// "limited" on a guessed mapping would be worse than showing the record and
/// letting it speak.
class AccountStandingSection extends StatefulWidget {
  const AccountStandingSection({required this.controller, super.key});

  final AccountStandingController controller;

  @override
  State<AccountStandingSection> createState() => _AccountStandingSectionState();
}

class _AccountStandingSectionState extends State<AccountStandingSection> {
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
      final standing = controller.standing;
      return Column(
        key: const ValueKey('settings-section-standing'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionHeader(
            title: 'Account Standing',
            subtitle: 'What Discord has recorded about this account.',
          ),
          if (controller.isLoading && standing == null)
            const Padding(
              key: ValueKey('standing-loading'),
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.error != null && standing == null)
            _StandingError(
              onRetry: () => unawaited(controller.load(refresh: true)),
            )
          else if (standing != null)
            ..._records(context, controller, standing),
        ],
      );
    },
  );

  List<Widget> _records(
    BuildContext context,
    AccountStandingController controller,
    AccountStanding standing,
  ) => [
    if (standing.username.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          standing.username,
          key: const ValueKey('standing-username'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    if (standing.isClear)
      const Padding(
        key: ValueKey('standing-clear'),
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Nothing is on record against this account.'),
      )
    else ...[
      if (standing.accountRecords.isNotEmpty)
        _RecordGroup(
          title: 'Against this account',
          records: standing.accountRecords,
          controller: controller,
        ),
      if (standing.guildRecords.isNotEmpty)
        _RecordGroup(
          title: 'Against servers you own',
          records: standing.guildRecords,
          controller: controller,
        ),
    ],
    if (standing.isDsaEligible)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'This account may appeal under the Digital Services Act.',
          key: const ValueKey('standing-dsa'),
          style: TextStyle(fontSize: 12, color: context.surfaces.muted),
        ),
      ),
    Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TextButton(
        key: const ValueKey('standing-refresh'),
        onPressed: controller.isLoading
            ? null
            : () => unawaited(controller.load(refresh: true)),
        child: const Text('Check again'),
      ),
    ),
  ];
}

class _RecordGroup extends StatelessWidget {
  const _RecordGroup({
    required this.title,
    required this.records,
    required this.controller,
  });

  final String title;
  final List<AccountClassification> records;
  final AccountStandingController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final record in records)
        Container(
          key: ValueKey('standing-record-${record.id}'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.surfaces.raised,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Discord localises these server-side, so an empty one
                      // is left as a record with no words rather than given
                      // wording this client invented.
                      record.title.isEmpty ? 'Recorded action' : record.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (record.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          record.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.surfaces.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (record.appealEligible)
                _ReviewButton(record: record, controller: controller),
            ],
          ),
        ),
    ],
  );
}

class _ReviewButton extends StatelessWidget {
  const _ReviewButton({required this.record, required this.controller});

  final AccountClassification record;
  final AccountStandingController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.hasRequestedReview(record.id)) {
      return Text(
        'Review requested',
        key: ValueKey('standing-requested-${record.id}'),
        style: TextStyle(fontSize: 12, color: context.surfaces.muted),
      );
    }
    if (controller.wasReviewRefused(record.id)) {
      // Discord declining to reopen a record is an answer, not a failure, so
      // it reads as one rather than as an error banner.
      return Text(
        'Cannot be reviewed again',
        key: ValueKey('standing-refused-${record.id}'),
        style: TextStyle(fontSize: 12, color: context.surfaces.muted),
      );
    }
    return TextButton(
      key: ValueKey('standing-review-${record.id}'),
      onPressed: () => unawaited(controller.requestReview(record.id)),
      child: const Text('Request review'),
    );
  }
}

class _StandingError extends StatelessWidget {
  const _StandingError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('standing-error'),
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Discord did not answer about this account.'),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('standing-retry'),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    ),
  );
}
