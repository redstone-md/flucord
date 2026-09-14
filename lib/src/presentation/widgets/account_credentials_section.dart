import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/user_profile_controller.dart';
import '../../theme/flucord_theme.dart';

/// Changing the account name and the password.
///
/// Both are gated on the current password, and both are kept apart from the
/// profile form: an ordinary edit of a bio must not carry a password, and a
/// name change must not ride along with one.
class AccountCredentialsSection extends StatefulWidget {
  const AccountCredentialsSection({required this.controller, super.key});

  final UserProfileController controller;

  @override
  State<AccountCredentialsSection> createState() =>
      _AccountCredentialsSectionState();
}

class _AccountCredentialsSectionState extends State<AccountCredentialsSection> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _currentPassword = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();

  List<TextEditingController> get _fields => [
    _username,
    _currentPassword,
    _newPassword,
  ];

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      field.addListener(_onTyped);
    }
  }

  void _onTyped() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field
        ..removeListener(_onTyped)
        // Cleared as well as disposed: these are credentials, and the page
        // that collected them should not leave them in memory behind it.
        ..clear()
        ..dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return Column(
        key: const ValueKey('account-credentials'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Account name', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            // Worth saying, because the two are separate fields on Discord
            // and changing the wrong one is a surprise.
            'Not your display name. This is the name people type to add you.',
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('credentials-username'),
            controller: _username,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'New account name',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('credentials-current-password'),
            controller: _currentPassword,
            obscureText: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Current password',
              helperText: 'Used for this one request and then forgotten.',
            ),
          ),
          const SizedBox(height: 8),
          if (controller.wasCredentialChangeRefused)
            Padding(
              key: const ValueKey('credentials-refused'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                // Discord refuses a wrong password and a taken name the same
                // way, so this does not claim to know which it was.
                'Discord would not take that. The password may be wrong, or '
                'the name already taken.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          FilledButton.tonal(
            key: const ValueKey('credentials-save-username'),
            onPressed: controller.isSaving || !_canChangeUsername
                ? null
                : () => unawaited(_changeUsername(controller)),
            child: const Text('Change account name'),
          ),
          const SizedBox(height: 24),
          Text('Password', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('credentials-new-password'),
            controller: _newPassword,
            obscureText: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'New password',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const ValueKey('credentials-save-password'),
            onPressed: controller.isSaving || !_canChangePassword
                ? null
                : () => unawaited(_changePassword(controller)),
            child: const Text('Change password'),
          ),
          const SizedBox(height: 4),
          Text(
            'Discord signs this device back in afterwards. Other devices are '
            'signed out.',
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
          ),
        ],
      );
    },
  );

  bool get _canChangeUsername =>
      _username.text.trim().isNotEmpty && _currentPassword.text.isNotEmpty;

  bool get _canChangePassword =>
      _newPassword.text.isNotEmpty && _currentPassword.text.isNotEmpty;

  Future<void> _changeUsername(UserProfileController controller) async {
    final password = _currentPassword.text;
    // Cleared before the await rather than after: it should not sit in a
    // field while the request is in flight.
    _currentPassword.clear();
    final accepted = await controller.changeUsername(
      username: _username.text,
      password: password,
    );
    if (accepted) _username.clear();
  }

  Future<void> _changePassword(UserProfileController controller) async {
    final current = _currentPassword.text;
    final next = _newPassword.text;
    _currentPassword.clear();
    _newPassword.clear();
    await controller.changePassword(
      currentPassword: current,
      newPassword: next,
    );
  }
}
