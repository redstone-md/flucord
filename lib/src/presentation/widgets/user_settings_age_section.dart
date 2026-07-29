import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/age_verification_controller.dart';
import '../../domain/age_verification.dart';
import '../../theme/flucord_theme.dart';
import 'user_settings_controls.dart';

/// The ways Discord will let this account prove its age.
///
/// Every one of them is carried out by somebody else. This page names what is
/// on offer and opens the chosen one outside the application, which is the
/// whole of Flucord's part in it.
class AgeVerificationSection extends StatefulWidget {
  const AgeVerificationSection({required this.controller, super.key});

  final AgeVerificationController controller;

  @override
  State<AgeVerificationSection> createState() => _AgeVerificationSectionState();
}

class _AgeVerificationSectionState extends State<AgeVerificationSection> {
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
      return Column(
        key: const ValueKey('settings-section-age'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionHeader(
            title: 'Age Verification',
            subtitle: 'Ways Discord will accept a proof of age.',
          ),
          Text(
            // Said before anything else on the page: it is the thing somebody
            // most needs to know before handing over a document.
            'Each check is run by the company Discord names, on their own '
            'page. Nothing you submit passes through Flucord.',
            key: const ValueKey('age-disclaimer'),
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
          ),
          const SizedBox(height: 12),
          if (controller.isLoading && controller.methods.isEmpty)
            const Padding(
              key: ValueKey('age-loading'),
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.error != null && controller.methods.isEmpty)
            _AgeError(onRetry: () => unawaited(controller.load(refresh: true)))
          else ...[
            if (controller.refusedMethod case final refused?)
              Padding(
                key: const ValueKey('age-refused'),
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Discord will not start ${refused.label} for this account.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (controller.methodNeedingVendorSurface case final blocked?)
              Padding(
                key: const ValueKey('age-vendor-surface'),
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${blocked.label} finishes inside the vendor\'s own app, '
                  'which Flucord does not carry. Use Discord for this one.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            for (final method in controller.methods)
              _MethodRow(method: method, controller: controller),
            if (controller.methods.isEmpty)
              const Padding(
                key: ValueKey('age-none'),
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Discord offers this account no way to verify.'),
              ),
          ],
        ],
      );
    },
  );
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({required this.method, required this.controller});

  final AgeVerificationMethod method;
  final AgeVerificationController controller;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('age-method-${method.method}'),
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
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
                method.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (method.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    method.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.surfaces.muted,
                    ),
                  ),
                ),
              if (_provider.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Run by $_provider',
                    key: ValueKey('age-provider-${method.method}'),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.surfaces.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        TextButton(
          key: ValueKey('age-start-${method.method}'),
          onPressed: controller.isStarting
              ? null
              : () => unawaited(controller.start(method)),
          child: const Text('Start'),
        ),
      ],
    ),
  );

  /// Who to name as running the check. Discord sometimes names a provider
  /// separately from the vendor; either is better than naming nobody.
  String get _provider =>
      method.providedBy.isNotEmpty ? method.providedBy : method.vendor;
}

class _AgeError extends StatelessWidget {
  const _AgeError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('age-error'),
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Discord did not list any way to verify.'),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('age-retry'),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    ),
  );
}
