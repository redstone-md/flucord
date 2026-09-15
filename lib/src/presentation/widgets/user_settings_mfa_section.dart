import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/multi_factor_auth_controller.dart';
import '../../domain/multi_factor_auth.dart';
import '../../theme/flucord_theme.dart';
import 'user_settings_controls.dart';

/// Two-factor authentication: add an authenticator or a security key, or
/// take one off.
///
/// The secret is shown once, while it is being added, and never again. If it
/// is lost before the first code works, the enrolment is started over, which
/// is safer than keeping a credential around to show a second time.
class MfaSettingsSection extends StatefulWidget {
  const MfaSettingsSection({required this.controller, super.key});

  final MultiFactorAuthController controller;

  @override
  State<MfaSettingsSection> createState() => _MfaSettingsSectionState();
}

class _MfaSettingsSectionState extends State<MfaSettingsSection> {
  final TextEditingController _code = TextEditingController();

  /// Typed for one request and never kept: this is the account password, and
  /// the field is cleared the moment the request that needed it is sent.
  final TextEditingController _password = TextEditingController();

  /// The name the new security key gets. Nothing secret about it: it is the
  /// label the key is listed by.
  final TextEditingController _securityKeyName = TextEditingController();

  /// The password a security key needs, kept apart from the other one because
  /// the two blocks ask at different times.
  final TextEditingController _securityKeyPassword = TextEditingController();

  @override
  void initState() {
    super.initState();
    _code.addListener(_onFieldChanged);
    _password.addListener(_onFieldChanged);
    _securityKeyName.addListener(_onFieldChanged);
    _securityKeyPassword.addListener(_onFieldChanged);
    unawaited(widget.controller.loadSecurityKeys());
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _code
      ..removeListener(_onFieldChanged)
      ..dispose();
    _password
      ..removeListener(_onFieldChanged)
      ..clear()
      ..dispose();
    _securityKeyName
      ..removeListener(_onFieldChanged)
      ..dispose();
    _securityKeyPassword
      ..removeListener(_onFieldChanged)
      ..clear()
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
            subtitle:
                'A second factor on top of the password: an app, a security '
                'key, or a text message.',
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
    const SizedBox(height: 20),
    ..._securityKeys(context, controller),
    const SizedBox(height: 20),
    Text('Text messages', style: Theme.of(context).textTheme.titleSmall),
    const SizedBox(height: 4),
    Text(
      // Discord uses the number already on the account, so there is nothing
      // to type; saying so is better than an empty field nobody can fill.
      'Codes go to the phone number already on the account.',
      style: TextStyle(fontSize: 12, color: context.surfaces.muted),
    ),
    const SizedBox(height: 6),
    _PasswordField(controller: _password),
    const SizedBox(height: 8),
    Row(
      children: [
        TextButton(
          key: const ValueKey('mfa-sms-enable'),
          onPressed: controller.isBusy
              ? null
              : () => unawaited(controller.enableSms()),
          child: const Text('Use text messages'),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: const ValueKey('mfa-sms-disable'),
          onPressed: controller.isBusy || _password.text.isEmpty
              ? null
              : () => unawaited(_disableSms(controller)),
          child: const Text('Stop using them'),
        ),
      ],
    ),
    const SizedBox(height: 20),
    Text('Backup codes', style: Theme.of(context).textTheme.titleSmall),
    const SizedBox(height: 4),
    Text(
      'Your password and a current code, because these are the way back in.',
      style: TextStyle(fontSize: 12, color: context.surfaces.muted),
    ),
    const SizedBox(height: 8),
    Row(
      children: [
        TextButton(
          key: const ValueKey('mfa-view-codes'),
          onPressed: controller.isBusy || !_canReveal
              ? null
              : () => unawaited(_reveal(controller, regenerate: false)),
          child: const Text('Show them'),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: const ValueKey('mfa-regenerate-codes'),
          onPressed: controller.isBusy || !_canReveal
              ? null
              : () => unawaited(_reveal(controller, regenerate: true)),
          child: const Text('Make new ones'),
        ),
      ],
    ),
  ];

  bool get _canReveal =>
      _password.text.isNotEmpty && _code.text.trim().length >= 6;

  /// The security keys group: what is registered, and adding one.
  ///
  /// Windows makes the key itself, so there is nothing to type but a name
  /// and the password that proves the ask is really this account's.
  List<Widget> _securityKeys(
    BuildContext context,
    MultiFactorAuthController controller,
  ) {
    if (!controller.isSecurityKeyCeremonyAvailable) {
      return [
        Text('Security keys', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'This machine has no platform authenticator Flucord can use for a '
          'security key.',
          key: const ValueKey('mfa-security-key-unavailable'),
          style: TextStyle(fontSize: 12, color: context.surfaces.muted),
        ),
      ];
    }
    return [
      Text('Security keys', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
        'Windows makes a key that stays on this machine and proves it is you '
        'with your face, fingerprint, or PIN.',
        style: TextStyle(fontSize: 12, color: context.surfaces.muted),
      ),
      const SizedBox(height: 8),
      if (controller.securityKeyRefusal case final refusal?)
        Padding(
          key: const ValueKey('mfa-security-key-refusal'),
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            switch (refusal) {
              MfaSecurityKeyRefusal.passwordRefused =>
                'That password was not accepted.',
              MfaSecurityKeyRefusal.keyDeclined =>
                'The prompt was closed before a key was made.',
              MfaSecurityKeyRefusal.registrationRefused =>
                'Discord would not take the key this machine made.',
              MfaSecurityKeyRefusal.removalRefused =>
                'Discord refused. Check the password; the key may already '
                    'be gone.',
            },
            style: TextStyle(
              fontSize: 12,
              color: refusal == MfaSecurityKeyRefusal.keyDeclined
                  ? context.surfaces.muted
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      if (controller.securityKeyStage == MfaSecurityKeyStage.prompting)
        const Padding(
          key: ValueKey('mfa-security-key-prompting'),
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Windows is asking you to prove it is you.'),
        )
      else if (controller.securityKeyStage == MfaSecurityKeyStage.added) ...[
        Text(
          'Added ${controller.addedSecurityKey?.name ?? 'the key'}. It '
          'answers for this account now.',
          key: const ValueKey('mfa-security-key-added'),
          style: const TextStyle(fontSize: 12, color: FlucordColors.success),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('mfa-security-key-done'),
          onPressed: controller.dismissAddedSecurityKey,
          child: const Text('Done'),
        ),
      ] else ...[
        TextField(
          key: const ValueKey('mfa-security-key-name'),
          controller: _securityKeyName,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Name this key',
            helperText: 'Shown in this list only.',
          ),
        ),
        const SizedBox(height: 8),
        _PasswordField(
          fieldKey: const ValueKey('mfa-security-key-password'),
          controller: _securityKeyPassword,
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const ValueKey('mfa-security-key-add'),
          onPressed:
              controller.isBusy ||
                  _securityKeyName.text.trim().isEmpty ||
                  _securityKeyPassword.text.isEmpty
              ? null
              : () => unawaited(_addSecurityKey(controller)),
          child: const Text('Add a security key'),
        ),
      ],
      const SizedBox(height: 8),
      for (final key in controller.securityKeys)
        _SecurityKeyRow(
          key: ValueKey('mfa-security-key-${key.id}'),
          securityKey: key,
          enabled: !controller.isBusy && _securityKeyPassword.text.isNotEmpty,
          onRemove: () => unawaited(_removeSecurityKey(controller, key)),
        ),
      if (controller.securityKeys.isEmpty)
        Text(
          'No security keys are on this account yet.',
          key: const ValueKey('mfa-security-key-none'),
          style: TextStyle(fontSize: 12, color: context.surfaces.muted),
        ),
    ];
  }

  Future<void> _addSecurityKey(MultiFactorAuthController controller) async {
    final name = _securityKeyName.text;
    final password = _securityKeyPassword.text;
    // Cleared before the await, so the password is not sitting in a field
    // while Windows asks its question.
    _securityKeyPassword.clear();
    await controller.beginSecurityKeyEnrolment(name: name, password: password);
    if (controller.securityKeyStage == MfaSecurityKeyStage.added) {
      _securityKeyName.clear();
    }
  }

  Future<void> _removeSecurityKey(
    MultiFactorAuthController controller,
    SecurityKey securityKey,
  ) async {
    final password = _securityKeyPassword.text;
    _securityKeyPassword.clear();
    await controller.removeSecurityKey(securityKey, password);
  }

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
      'Two-factor authentication is on. Write these codes down; they are '
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

  Future<void> _disableSms(MultiFactorAuthController controller) async {
    final password = _password.text;
    // Cleared before the await, so it is not sitting in a field while the
    // request is in flight.
    _password.clear();
    await controller.disableSms(password);
  }

  Future<void> _reveal(
    MultiFactorAuthController controller, {
    required bool regenerate,
  }) async {
    final password = _password.text;
    final code = _code.text;
    _password.clear();
    _code.clear();
    await controller.revealBackupCodes(
      password: password,
      code: code,
      regenerate: regenerate,
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({this.fieldKey, required this.controller});

  /// Null keeps the shared key the rest of this page has always used; the
  /// security-key block names its own so the two fields can be told apart.
  final Key? fieldKey;

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey ?? const ValueKey('mfa-password'),
    controller: controller,
    obscureText: true,
    decoration: const InputDecoration(
      isDense: true,
      labelText: 'Account password',
      helperText: 'Used for this one request and then forgotten.',
    ),
  );
}

/// One registered security key, with its removal next to it.
class _SecurityKeyRow extends StatelessWidget {
  const _SecurityKeyRow({
    super.key,
    required this.securityKey,
    required this.enabled,
    required this.onRemove,
  });

  final SecurityKey securityKey;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final created = securityKey.createdAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              securityKey.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (created != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'added ${created.year}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 11, color: context.surfaces.muted),
              ),
            ),
          TextButton(
            key: ValueKey('mfa-security-key-remove-${securityKey.id}'),
            onPressed: enabled ? onRemove : null,
            child: const Text('Remove'),
          ),
        ],
      ),
    );
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
