import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/account_data_package_controller.dart';
import '../../domain/account_data_package.dart';
import '../../theme/flucord_theme.dart';
import 'user_settings_controls.dart';

/// The account's data package: a request that can be started, and the state
/// of the one running.
///
/// The archive itself never passes through the client. Discord collects it
/// and emails a download link, so this page's whole job is to start the
/// collection and to say where it stands, and it says so before anything
/// else.
class DataPackageSettingsSection extends StatefulWidget {
  const DataPackageSettingsSection({required this.controller, super.key});

  final AccountDataPackageController controller;

  @override
  State<DataPackageSettingsSection> createState() =>
      _DataPackageSettingsSectionState();
}

class _DataPackageSettingsSectionState
    extends State<DataPackageSettingsSection> {
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
      final package = controller.package;
      return Column(
        key: const ValueKey('settings-section-data-package'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionHeader(
            title: 'Data Package',
            subtitle:
                'Everything Discord holds on this account, collected '
                'into one archive.',
          ),
          Text(
            'The archive arrives as a download link sent to the account\'s '
            'email address. Collecting it can take up to thirty days, and '
            'only one request can run at a time.',
            key: const ValueKey('data-package-explainer'),
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
          ),
          const SizedBox(height: 12),
          if (controller.isLoading && package == null)
            const Padding(
              key: ValueKey('data-package-loading'),
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.error != null && package == null)
            _DataPackageError(
              onRetry: () => unawaited(controller.load(refresh: true)),
            )
          else ...[
            if (controller.wasRefused)
              Padding(
                key: const ValueKey('data-package-refused'),
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Discord did not start one. The account needs a verified '
                  'email address, and only one request can run at a time.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (package == null)
              const Padding(
                key: ValueKey('data-package-none'),
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No request has been made yet.'),
              )
            else
              _StatusCard(package: package),
            const SizedBox(height: 8),
            if (package == null || !package.isRunning)
              FilledButton.tonal(
                key: const ValueKey('data-package-request'),
                onPressed: controller.isRequesting
                    ? null
                    : () => unawaited(controller.request()),
                child: const Text('Request the archive'),
              ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('data-package-refresh'),
              onPressed: controller.isLoading
                  ? null
                  : () => unawaited(controller.load(refresh: true)),
              child: const Text('Refresh'),
            ),
          ],
        ],
      );
    },
  );
}

/// Where one request stands, in plain words.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.package});

  final AccountDataPackage package;

  @override
  Widget build(BuildContext context) {
    final package = this.package;
    return Container(
      key: const ValueKey('data-package-status'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          switch (package.status) {
            DataPackageStatus.pending => Text(
              'Requested ${_when(package.createdAt)}. Waiting for Discord to '
              'start collecting it.',
              key: const ValueKey('data-package-status-pending'),
            ),
            DataPackageStatus.processing => Text(
              'Collecting. ${package.progressPercent}% done.',
              key: const ValueKey('data-package-status-processing'),
            ),
            DataPackageStatus.completed => Text(
              'Collected ${_when(package.completedAt)}. The download link '
              'went to the account\'s email address'
              '${package.expiresAt != null ? ' and expires ${_when(package.expiresAt)}' : ''}.',
              key: const ValueKey('data-package-status-completed'),
            ),
            DataPackageStatus.failed => Text(
              'It failed${package.errorMessage == null ? '' : ': ${package.errorMessage}'}. '
              'You can ask again.',
              key: const ValueKey('data-package-status-failed'),
            ),
          },
          if (package.status == DataPackageStatus.processing) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              key: const ValueKey('data-package-progress'),
              value: package.progressPercent / 100,
              minHeight: 4,
            ),
          ],
          if (package.progressStep != null &&
              package.status == DataPackageStatus.processing)
            Padding(
              key: const ValueKey('data-package-step'),
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                package.progressStep!,
                style: TextStyle(fontSize: 12, color: context.surfaces.muted),
              ),
            ),
        ],
      ),
    );
  }

  static String _when(DateTime? when) {
    if (when == null || when.year <= 1970) return 'recently';
    final local = when.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

class _DataPackageError extends StatelessWidget {
  const _DataPackageError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('data-package-error'),
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Discord did not say where the request stands.'),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('data-package-retry'),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    ),
  );
}
