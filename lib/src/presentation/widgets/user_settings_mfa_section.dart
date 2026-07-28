import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/multi_factor_auth_controller.dart';
import '../../theme/flucord_theme.dart';
import 'user_settings_controls.dart';

/// Two-factor authentication: add an authenticator, or take one off.
///
/// The secret is shown once, while it is being added, and never again. If it
/// is lost before the first code works, the enrolment is started over — which
/// is safer than keeping a credential around to show a second time.
class MfaSettingsSection extends StatefulWidget {
  const MfaSettingsSection({required this.controller, super.key});

  final MultiFactorAuthController controller;

  @override
  State<MfaSettingsSection> createState() => _MfaSettingsSectionState();
}

class _MfaSettingsSectionState extends State<MfaSettingsSection> {
  final TextEditingController _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _code.addListener(_onCodeChanged);
  }

  void _onCodeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _code
      ..removeListener(_onCodeChanged)
      ..dispose();
    // The secret and the backup codes do not outlive the page that showed
    // them; both are credentials.
    widget.controller.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return Column(
        key: const ValueKey('settings-section-mfa'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionHeader(
            title: 'Two-Factor Authentication',
            subtitle: 'A code from an app, on top of the password.',
          ),
          if (controller.error != null)
            Padding(
              key: const ValueKey('mfa-error'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Discord did not answer. Nothing was changed.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ...switch (controller.stage) {
            MfaEnrolmentStage.idle => _idle(context, controller),
            MfaEnrolmentStage.awaitingCode => _awaiting(context, controller),
            MfaEnrolmentStage.enrolled => _enrolled(context, controller),
          },
        ],
      );
    },
  );

  List<Widget> _idle(
    BuildContext context,
    MultiFactorAuthController controller,
  ) => [
    const Text(
      'Add an authenticator app, or remove the one already on this account.',
    ),
    const SizedBox(height: 12),
    FilledButton.tonal(
      key: const ValueKey('mfa-begin'),
      onPressed: controller.isBusy ? null : controller.beginEnrolment,
      child: const Text('Add an authenticator'),
    ),
    const SizedBox(height: 20),
    Text('Remove one', style: Theme.of(context).textTheme.titleSmall),
    const SizedBox(height: 6),
    _CodeField(
      fieldKey: const ValueKey('mfa-disable-code'),
      controller: _code,
      label: 'Current code',
      refused: controller.wasCodeRefused,
    ),
    const SizedBox(height: 8),
    TextButton(
      key: const ValueKey('mfa-disable'),
      onPressed: controller.isBusy || _code.text.trim().length < 6
          ? null
          : () => unawaited(_disable(controller)),
      child: const Text('Turn two-factor off'),
    ),
  ];

  List<Widget> _awaiting(
    BuildContext context,
    MultiFactorAuthController controller,
  ) => [
    const Text('Add this to your authenticator app, then enter a code.'),
    const SizedBox(height: 10),
    SelectableText(
      controller.secret?.readable ?? '',
      key: const ValueKey('mfa-secret'),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    ),
    const SizedBox(height: 4),
    Text(
      'Shown once. If you lose it before the first code works, start again.',
      style: TextStyle(fontSize: 12, color: context.surfaces.muted),
    ),
    const SizedBox(height: 12),
    _CodeField(
      fieldKey: const ValueKey('mfa-enrol-code'),
      controller: _code,
      label: 'Code from the app',
      refused: controller.wasCodeRefused,
    ),
    const SizedBox(height: 8),
    Row(
      children: [
        FilledButton(
          key: const ValueKey('mfa-confirm'),
          onPressed: controller.isBusy || _code.text.trim().length < 6
              ? null
              : () => unawaited(_confirm(controller)),
          child: const Text('Turn two-factor on'),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: const ValueKey('mfa-cancel'),
          onPressed: controller.isBusy
              ? null
              : () {
                  _code.clear();
                  controller.reset();
                },
          child: const Text('Cancel'),
        ),
      ],
    ),
  ];

  List<Widget> _enrolled(
    BuildContext context,
    MultiFactorAuthController controller,
  ) => [
    const Text(
      'Two-factor authentication is on. Write these codes down — they are '
      'the way back in if the app is lost.',
      key: ValueKey('mfa-enrolled'),
    ),
    const SizedBox(height: 10),
    for (final code in controller.backupCodes)
      SelectableText(
        code,
        key: ValueKey('mfa-backup-$code'),
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    if (controller.backupCodes.isEmpty)
      Text(
        'Discord sent no backup codes.',
        key: const ValueKey('mfa-no-backup'),
        style: TextStyle(fontSize: 12, color: context.surfaces.muted),
      ),
    const SizedBox(height: 12),
    TextButton(
      key: const ValueKey('mfa-done'),
      onPressed: () {
        _code.clear();
        controller.reset();
      },
      child: const Text('I have written them down'),
    ),
  ];

  Future<void> _confirm(MultiFactorAuthController controller) async {
    final accepted = await controller.confirmEnrolment(_code.text);
    if (accepted) _code.clear();
  }

  Future<void> _disable(MultiFactorAuthController controller) async {
    final accepted = await controller.disable(_code.text);
    if (accepted) _code.clear();
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.refused,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final bool refused;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      isDense: true,
      labelText: label,
      // A wrong code is the ordinary case, not a fault, so it reads as one.
      errorText: refused
          ? 'That code was not accepted. Try the next one.'
          : null,
    ),
  );
}
