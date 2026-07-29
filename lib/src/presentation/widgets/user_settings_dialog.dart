import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/account_standing_controller.dart';
import '../../application/auth_session_controller.dart';
import '../../application/family_centre_controller.dart';
import '../../application/age_verification_controller.dart';
import '../../application/keybind_controller.dart';
import '../../application/multi_factor_auth_controller.dart';
import '../../application/user_profile_controller.dart';
import '../../application/user_settings_controller.dart';
import '../../domain/user_settings.dart';
import '../../domain/user_settings_repository.dart';
import '../../theme/flucord_theme.dart';
import 'user_profile_controls.dart';
import 'account_credentials_section.dart';
import 'user_profile_section.dart';
import 'user_settings_account_sections.dart';
import 'user_settings_devices_section.dart';
import 'user_settings_family_section.dart';
import 'user_settings_age_section.dart';
import 'user_settings_mfa_section.dart';
import 'user_settings_standing_section.dart';
import 'user_settings_sections.dart';
import 'keybind_section.dart';

/// The left-hand categories, in the order Discord lists the comparable ones.
enum UserSettingsCategory {
  profile('Profile', Icons.person_outline),
  appearance('Appearance', Icons.palette_outlined),
  chat('Chat', Icons.chat_bubble_outline),
  notifications('Notifications', Icons.notifications_none),
  privacy('Privacy', Icons.shield_outlined),
  standing('Account Standing', Icons.gavel_outlined),
  family('Family Center', Icons.family_restroom_outlined),
  devices('Devices', Icons.devices_outlined),
  security('Two-Factor', Icons.key_outlined),
  age('Age Verification', Icons.badge_outlined),
  keybinds('Keybinds', Icons.keyboard_outlined),
  language('Language', Icons.translate),
  status('Status', Icons.mood_outlined);

  const UserSettingsCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Discord's user settings screen, for the settings Flucord can speak for.
class UserSettingsDialog extends StatefulWidget {
  const UserSettingsDialog({
    required this.controller,
    this.profileController,
    this.standingController,
    this.familyController,
    this.sessionController,
    this.mfaController,
    this.ageController,
    this.keybindController,
    super.key,
  });

  /// Below this width the category rail becomes a scrolling strip so the pane
  /// keeps its full width for the controls.
  static const railBreakpoint = 720.0;

  final UserSettingsController controller;

  /// Null when the session has no editable profile — the demo and bot
  /// transports — in which case the category explains itself instead.
  final UserProfileController? profileController;

  /// Answers for the account's safety record, or null on a transport with
  /// none. Like the profile, it is not gated on the settings store.
  final AccountStandingController? standingController;

  /// Answers for the family centre, or null on a transport with none.
  final FamilyCentreController? familyController;

  /// Answers for the account's sessions, or null on a transport with none.
  final AuthSessionController? sessionController;

  /// Answers for two-factor authentication, or null where it cannot be set.
  final MultiFactorAuthController? mfaController;

  /// Answers for age verification, or null where none is offered.
  final AgeVerificationController? ageController;

  /// The keyboard shortcuts. Local to the machine, so it is present whatever
  /// the session is — including the demo one.
  final KeybindController? keybindController;

  static Future<void> show(
    BuildContext context, {
    required UserSettingsController controller,
    UserProfileController? profileController,
    AccountStandingController? standingController,
    FamilyCentreController? familyController,
    AuthSessionController? sessionController,
    MultiFactorAuthController? mfaController,
    AgeVerificationController? ageController,
    KeybindController? keybindController,
  }) => showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (_) => UserSettingsDialog(
      controller: controller,
      profileController: profileController,
      standingController: standingController,
      familyController: familyController,
      sessionController: sessionController,
      mfaController: mfaController,
      ageController: ageController,
      keybindController: keybindController,
    ),
  );

  @override
  State<UserSettingsDialog> createState() => _UserSettingsDialogState();
}

class _UserSettingsDialogState extends State<UserSettingsDialog> {
  UserSettingsCategory _category = UserSettingsCategory.profile;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('user-settings-dialog'),
    insetPadding: const EdgeInsets.all(24),
    backgroundColor: context.surfaces.canvas,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 940, maxHeight: 720),
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= UserSettingsDialog.railBreakpoint;
            final navigation = _Navigation(
              selected: _category,
              horizontal: !wide,
              onSelected: (category) => setState(() => _category = category),
            );
            final body = _Body(
              controller: widget.controller,
              profileController: widget.profileController,
              standingController: widget.standingController,
              familyController: widget.familyController,
              sessionController: widget.sessionController,
              mfaController: widget.mfaController,
              ageController: widget.ageController,
              keybindController: widget.keybindController,
              category: _category,
            );
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 232, child: navigation),
                      VerticalDivider(width: 1, color: context.surfaces.border),
                      Expanded(child: body),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      navigation,
                      Divider(height: 1, color: context.surfaces.border),
                      Expanded(child: body),
                    ],
                  );
          },
        ),
      ),
    ),
  );
}

class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.selected,
    required this.horizontal,
    required this.onSelected,
  });

  final UserSettingsCategory selected;
  final bool horizontal;
  final ValueChanged<UserSettingsCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final category in UserSettingsCategory.values)
        _NavigationTile(
          category: category,
          selected: category == selected,
          compact: horizontal,
          onPressed: () => onSelected(category),
        ),
    ];
    if (!horizontal) {
      return ColoredBox(
        color: context.surfaces.surface,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                'User settings',
                style: TextStyle(
                  color: context.surfaces.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ...tiles,
          ],
        ),
      );
    }
    return ColoredBox(
      color: context.surfaces.surface,
      child: SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: [
            for (final tile in tiles)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: tile,
              ),
          ],
        ),
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.category,
    required this.selected,
    required this.compact,
    required this.onPressed,
  });

  final UserSettingsCategory category;
  final bool selected;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? Theme.of(context).colorScheme.onSurface
        : context.surfaces.muted;
    final label = Text(
      category.label,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: foreground,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 1),
      child: Material(
        color: selected ? context.surfaces.raised : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          key: ValueKey('settings-nav-${category.name}'),
          borderRadius: BorderRadius.circular(4),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(category.icon, size: 15, color: foreground),
                const SizedBox(width: 8),
                // The horizontal strip hands its children unbounded width, so
                // only the rail's column can hand the label a flex factor.
                if (compact) label else Flexible(child: label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.profileController,
    required this.standingController,
    required this.familyController,
    required this.sessionController,
    required this.mfaController,
    required this.ageController,
    required this.keybindController,
    required this.category,
  });

  final UserSettingsController controller;
  final UserProfileController? profileController;
  final AccountStandingController? standingController;
  final FamilyCentreController? familyController;
  final AuthSessionController? sessionController;
  final MultiFactorAuthController? mfaController;
  final AgeVerificationController? ageController;
  final KeybindController? keybindController;
  final UserSettingsCategory category;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                category.label,
                style: TextStyle(
                  color: context.surfaces.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('user-settings-close'),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
      if (controller.writeError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(
            key: const ValueKey('user-settings-write-error'),
            'Discord did not accept the last change.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 11,
            ),
          ),
        ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: _content(context),
        ),
      ),
    ],
  );

  Widget _content(BuildContext context) {
    // The profile lives on a different route from the settings store, so it
    // answers for itself rather than being gated on settings having loaded.
    if (category == UserSettingsCategory.profile) {
      final profile = profileController;
      if (profile == null) {
        return const ProfileNotice(
          key: ValueKey('user-profile-unavailable'),
          icon: Icons.cloud_off_outlined,
          message:
              'Connect a Discord account to edit its profile. The demo and '
              'bot transports have no profile behind them.',
        );
      }
      return ListenableBuilder(
        listenable: profile,
        builder: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserProfileSection(controller: profile),
            const SizedBox(height: 28),
            // Below the profile rather than beside it: these two change what
            // somebody signs in with, and mixing them into the same form is
            // how a bio edit ends up asking for a password.
            AccountCredentialsSection(controller: profile),
          ],
        ),
      );
    }
    // Keybinds are the machine's, not the account's: no settings store is
    // involved and none is waited for.
    if (category == UserSettingsCategory.keybinds) {
      final keybinds = keybindController;
      if (keybinds == null) {
        return const ProfileNotice(
          key: ValueKey('user-keybinds-unavailable'),
          icon: Icons.keyboard_outlined,
          message: 'Keybinds are unavailable in this build.',
        );
      }
      return KeybindSection(controller: keybinds);
    }
    // The safety hub is its own route too: an account with no settings store
    // still has a record, and gating this on settings would hide it.
    if (category == UserSettingsCategory.standing) {
      final standing = standingController;
      if (standing == null) {
        return const ProfileNotice(
          key: ValueKey('user-standing-unavailable'),
          icon: Icons.cloud_off_outlined,
          message:
              'Connect a Discord account to see what is on its record. The '
              'demo and bot transports have none.',
        );
      }
      return AccountStandingSection(controller: standing);
    }
    // The family centre is its own route as well, for the same reason.
    if (category == UserSettingsCategory.family) {
      final family = familyController;
      if (family == null) {
        return const ProfileNotice(
          key: ValueKey('user-family-unavailable'),
          icon: Icons.cloud_off_outlined,
          message:
              'Connect a Discord account to see its family centre. The demo '
              'and bot transports have none.',
        );
      }
      return FamilyCentreSection(controller: family);
    }
    if (category == UserSettingsCategory.devices) {
      final sessions = sessionController;
      if (sessions == null) {
        return const ProfileNotice(
          key: ValueKey('user-devices-unavailable'),
          icon: Icons.cloud_off_outlined,
          message:
              'Connect a Discord account to see where it is signed in. The '
              'demo and bot transports have one session and no route to list '
              'it.',
        );
      }
      return DevicesSettingsSection(controller: sessions);
    }
    if (category == UserSettingsCategory.security) {
      final mfa = mfaController;
      if (mfa == null) {
        return const ProfileNotice(
          key: ValueKey('user-mfa-unavailable'),
          icon: Icons.cloud_off_outlined,
          message:
              'Connect a Discord account to manage two-factor authentication. '
              'The demo and bot transports have no account to secure.',
        );
      }
      return MfaSettingsSection(controller: mfa);
    }
    if (category == UserSettingsCategory.age) {
      final age = ageController;
      if (age == null) {
        return const ProfileNotice(
          key: ValueKey('user-age-unavailable'),
          icon: Icons.cloud_off_outlined,
          message:
              'Connect a Discord account to see how it can prove its age. '
              'The demo and bot transports have no account to verify.',
        );
      }
      return AgeVerificationSection(controller: age);
    }
    if (!controller.isAvailable) {
      return _Notice(
        key: const ValueKey('user-settings-unavailable'),
        icon: Icons.cloud_off_outlined,
        message:
            'Connect a Discord account to read and change its settings. '
            'The demo and bot transports have no account behind them.',
      );
    }
    final settings = controller.settings;
    if (settings == null) {
      if (controller.isLoading) {
        return const Center(
          key: ValueKey('user-settings-loading'),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      return Column(
        key: const ValueKey('user-settings-error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Notice(
            icon: Icons.error_outline,
            message: 'Discord did not return your settings.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => unawaited(controller.load()),
            child: const Text('Try again'),
          ),
        ],
      );
    }
    return _section(settings);
  }

  Widget _section(UserSettings settings) => switch (category) {
    // Handled before the settings store is consulted.
    UserSettingsCategory.profile ||
    UserSettingsCategory.keybinds => const SizedBox.shrink(),
    UserSettingsCategory.appearance => AppearanceSettingsSection(
      settings: settings,
      onEdit: _edit,
    ),
    UserSettingsCategory.chat => ChatSettingsSection(
      settings: settings,
      onEdit: _edit,
    ),
    UserSettingsCategory.notifications => NotificationSettingsSection(
      settings: settings,
      onEdit: _edit,
    ),
    UserSettingsCategory.privacy => PrivacySettingsSection(
      settings: settings,
      onEdit: _edit,
    ),
    // Handled before the settings store is consulted.
    UserSettingsCategory.standing => const SizedBox.shrink(),
    UserSettingsCategory.family => const SizedBox.shrink(),
    UserSettingsCategory.devices => const SizedBox.shrink(),
    UserSettingsCategory.security => const SizedBox.shrink(),
    UserSettingsCategory.age => const SizedBox.shrink(),
    UserSettingsCategory.language => LanguageSettingsSection(
      settings: settings,
    ),
    UserSettingsCategory.status => StatusSettingsSection(
      settings: settings,
      onEdit: _edit,
    ),
  };

  void _edit(UserSettingsPatch patch) => unawaited(controller.apply(patch));
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: context.surfaces.muted),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          message,
          style: TextStyle(color: context.surfaces.muted, fontSize: 12),
        ),
      ),
    ],
  );
}
