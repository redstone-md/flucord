import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/account_connections_controller.dart';
import '../../application/account_data_package_controller.dart';
import '../../application/accessibility_controller.dart';
import '../../application/account_entitlements_controller.dart';
import '../../application/app_authorisation_controller.dart';
import '../../application/account_standing_controller.dart';
import '../../application/family_centre_controller.dart';
import '../../application/auth_session_controller.dart';
import '../../application/keybind_controller.dart';
import '../../application/age_verification_controller.dart';
import '../../application/streamer_mode_controller.dart';
import '../../application/stream_quality_controller.dart';
import '../../application/theme_controller.dart';
import '../../application/voice_controller.dart';
import '../../application/multi_factor_auth_controller.dart';
import '../../application/user_profile_controller.dart';
import '../../application/user_settings_controller.dart';
import '../../domain/user_settings.dart';
import '../../domain/user_settings_repository.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'user_profile_controls.dart';
import 'account_credentials_section.dart';
import 'user_profile_section.dart';
import 'user_settings_connections_section.dart';
import 'user_settings_data_package_section.dart';
import 'user_settings_entitlements_section.dart';
import 'user_settings_apps_section.dart';
import 'user_settings_family_section.dart';
import 'user_settings_devices_section.dart';
import 'user_settings_age_section.dart';
import 'user_settings_mfa_section.dart';
import 'user_settings_standing_section.dart';
import 'user_settings_sections.dart';
import 'user_settings_account_sections.dart';
import 'keybind_section.dart';
import 'stream_quality_section.dart';
import 'accessibility_section.dart';
import 'streamer_mode_section.dart';
import 'theme_section.dart';
import 'voice_devices_section.dart';
import 'flucord_button.dart';
import 'settings_layout.dart';

/// The two groups the navigation lists pages under.
enum UserSettingsGroup {
  user('User settings'),
  app('App settings');

  const UserSettingsGroup(this.label);

  final String label;
}

/// The left-hand categories, in the order Discord lists the comparable ones.
/// What belongs to the account is under [UserSettingsGroup.user]; what
/// belongs to this machine and app is under [UserSettingsGroup.app].
enum UserSettingsCategory {
  profile('Profile', FlucordIcons.profile, UserSettingsGroup.user),
  appearance('Appearance', FlucordIcons.appearance, UserSettingsGroup.app),
  chat('Chat', FlucordIcons.chat, UserSettingsGroup.app),
  notifications(
    'Notifications',
    FlucordIcons.notifications,
    UserSettingsGroup.app,
  ),
  privacy('Privacy', FlucordIcons.privacy, UserSettingsGroup.user),
  standing('Account Standing', FlucordIcons.standing, UserSettingsGroup.user),
  family('Family Center', FlucordIcons.family, UserSettingsGroup.user),
  devices('Devices', FlucordIcons.devices, UserSettingsGroup.user),
  connections('Connections', FlucordIcons.link, UserSettingsGroup.user),
  entitlements(
    'Entitlements',
    FlucordIcons.entitlements,
    UserSettingsGroup.user,
  ),
  security('Two-Factor', FlucordIcons.twoFactor, UserSettingsGroup.user),
  age('Age Verification', FlucordIcons.ageVerification, UserSettingsGroup.user),
  apps('App Authorisation', FlucordIcons.apps, UserSettingsGroup.user),
  dataPackage('Data Package', FlucordIcons.download, UserSettingsGroup.user),
  keybinds('Keybinds', FlucordIcons.keyboard, UserSettingsGroup.app),
  streamer('Streamer Mode', FlucordIcons.streamerMode, UserSettingsGroup.app),
  accessibility(
    'Accessibility',
    FlucordIcons.accessibility,
    UserSettingsGroup.app,
  ),
  voice('Voice & Video', FlucordIcons.mic, UserSettingsGroup.app),
  themes('Themes', FlucordIcons.themes, UserSettingsGroup.app),
  language('Language', FlucordIcons.language, UserSettingsGroup.app),
  status('Status', FlucordIcons.emoji, UserSettingsGroup.user);

  const UserSettingsCategory(this.label, this.icon, this.group);

  final String label;
  final FlucordIconData icon;
  final UserSettingsGroup group;
}

/// Discord's user settings screen, for the settings Flucord can speak for.
class UserSettingsDialog extends StatefulWidget {
  const UserSettingsDialog({
    required this.controller,
    this.profileController,
    this.standingController,
    this.familyController,
    this.sessionController,
    this.connectionsController,
    this.entitlementsController,
    this.dataPackageController,
    this.appAuthorisationController,
    this.mfaController,
    this.ageController,
    this.keybindController,
    this.streamerModeController,
    this.accessibilityController,
    this.streamQualityController,
    this.themeController,
    this.voiceController,
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

  /// Answers for the account's third-party connections, or null on a
  /// transport with none to read or change.
  final AccountConnectionsController? connectionsController;

  /// Answers for what the account holds, or null on a transport that reads
  /// nothing.
  final AccountEntitlementsController? entitlementsController;

  /// Answers for the account's data package, or null on a transport with no
  /// account to collect one from.
  final AccountDataPackageController? dataPackageController;

  /// Answers for authorising an app into a server, or null on a transport
  /// that cannot consent to one.
  final AppAuthorisationController? appAuthorisationController;

  /// Answers for two-factor authentication, or null where it cannot be set.
  final MultiFactorAuthController? mfaController;

  /// Answers for age verification, or null where none is offered.
  final AgeVerificationController? ageController;

  /// The keyboard shortcuts. Local to the machine, so it is present whatever
  /// the session is — including the demo one.
  final KeybindController? keybindController;

  /// Streamer mode, local for the same reason.
  final StreamerModeController? streamerModeController;

  /// The interface adjustments, local like the rest of this run of
  /// controllers: a screen's size belongs to the machine in front of it.
  final AccessibilityController? accessibilityController;

  /// The bitrates a share and a camera are encoded at. Local like the rest of
  /// this run of controllers: the machine's connection is what they describe.
  final StreamQualityController? streamQualityController;

  /// The installed themes, which belong to the machine rather than the
  /// account and so are there whatever the session is.
  final ThemeController? themeController;

  /// The audio devices, which belong to the machine like the themes do.
  final VoiceController? voiceController;

  static Future<void> show(
    BuildContext context, {
    required UserSettingsController controller,
    UserProfileController? profileController,
    AccountStandingController? standingController,
    FamilyCentreController? familyController,
    AuthSessionController? sessionController,
    AccountConnectionsController? connectionsController,
    AccountEntitlementsController? entitlementsController,
    AccountDataPackageController? dataPackageController,
    AppAuthorisationController? appAuthorisationController,
    MultiFactorAuthController? mfaController,
    AgeVerificationController? ageController,
    KeybindController? keybindController,
    StreamerModeController? streamerModeController,
    AccessibilityController? accessibilityController,
    StreamQualityController? streamQualityController,
    ThemeController? themeController,
    VoiceController? voiceController,
  }) => showDialog<void>(
    context: context,
    builder: (_) => UserSettingsDialog(
      controller: controller,
      profileController: profileController,
      standingController: standingController,
      familyController: familyController,
      sessionController: sessionController,
      connectionsController: connectionsController,
      entitlementsController: entitlementsController,
      dataPackageController: dataPackageController,
      appAuthorisationController: appAuthorisationController,
      mfaController: mfaController,
      ageController: ageController,
      keybindController: keybindController,
      streamerModeController: streamerModeController,
      accessibilityController: accessibilityController,
      streamQualityController: streamQualityController,
      themeController: themeController,
      voiceController: voiceController,
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
    // Loading notifies at once, and the screen behind this dialog listens. It
    // has to wait for the frame that is building now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.load());
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    key: const ValueKey('user-settings-dialog'),
    listenable: widget.controller,
    builder: (context, _) => SettingsLayout(
      compactWidth: UserSettingsDialog.railBreakpoint,
      closeKey: const ValueKey('user-settings-close'),
      title: _category.label,
      groups: [
        for (final group in UserSettingsGroup.values)
          SettingsNavGroup(
            heading: group.label,
            entries: [
              for (final category in UserSettingsCategory.values)
                if (category.group == group)
                  SettingsNavEntry(
                    key: ValueKey('settings-nav-${category.name}'),
                    label: category.label,
                    icon: category.icon,
                    selected: category == _category,
                    onPressed: () => setState(() => _category = category),
                  ),
            ],
          ),
      ],
      body: _Body(
        controller: widget.controller,
        profileController: widget.profileController,
        standingController: widget.standingController,
        familyController: widget.familyController,
        sessionController: widget.sessionController,
        connectionsController: widget.connectionsController,
        entitlementsController: widget.entitlementsController,
        dataPackageController: widget.dataPackageController,
        appAuthorisationController: widget.appAuthorisationController,
        mfaController: widget.mfaController,
        ageController: widget.ageController,
        keybindController: widget.keybindController,
        streamerModeController: widget.streamerModeController,
        accessibilityController: widget.accessibilityController,
        streamQualityController: widget.streamQualityController,
        themeController: widget.themeController,
        voiceController: widget.voiceController,
        category: _category,
      ),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.profileController,
    required this.standingController,
    required this.familyController,
    required this.sessionController,
    required this.connectionsController,
    required this.entitlementsController,
    required this.dataPackageController,
    required this.appAuthorisationController,
    required this.mfaController,
    required this.ageController,
    required this.keybindController,
    required this.streamerModeController,
    required this.accessibilityController,
    required this.streamQualityController,
    required this.themeController,
    required this.voiceController,
    required this.category,
  });

  final UserSettingsController controller;
  final UserProfileController? profileController;
  final AccountStandingController? standingController;
  final FamilyCentreController? familyController;
  final AuthSessionController? sessionController;
  final AccountConnectionsController? connectionsController;
  final AccountEntitlementsController? entitlementsController;
  final AccountDataPackageController? dataPackageController;
  final AppAuthorisationController? appAuthorisationController;
  final MultiFactorAuthController? mfaController;
  final AgeVerificationController? ageController;
  final KeybindController? keybindController;
  final StreamerModeController? streamerModeController;

  /// The interface adjustments, local like the keybinds.
  final AccessibilityController? accessibilityController;

  final StreamQualityController? streamQualityController;
  final ThemeController? themeController;
  final VoiceController? voiceController;
  final UserSettingsCategory category;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (controller.writeError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 4),
          child: Text(
            key: const ValueKey('user-settings-write-error'),
            'Discord did not accept the last change.',
            style: FlucordTextRole.caption.style.copyWith(
              color: context.surfaces.errorText,
            ),
          ),
        ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 8, 40, 24),
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
        return const _NeedsAccountNotice(
          key: ValueKey('user-profile-unavailable'),
          toDo: 'edit its profile',
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
    if (category == UserSettingsCategory.streamer) {
      final streamer = streamerModeController;
      if (streamer == null) {
        return const ProfileNotice(
          key: ValueKey('user-streamer-unavailable'),
          icon: Icons.videocam_off_outlined,
          message: 'Streamer mode is unavailable in this build.',
        );
      }
      return StreamerModeSection(controller: streamer);
    }
    // The accessibility dials are the machine's too: they describe the
    // screen in front of it rather than anything on the account.
    if (category == UserSettingsCategory.accessibility) {
      final accessibility = accessibilityController;
      if (accessibility == null) {
        return const ProfileNotice(
          key: ValueKey('user-accessibility-unavailable'),
          icon: Icons.accessibility_new,
          message: 'Accessibility settings are unavailable in this build.',
        );
      }
      return AccessibilitySection(controller: accessibility);
    }
    if (category == UserSettingsCategory.voice) {
      final voice = voiceController;
      final quality = streamQualityController;
      if (voice == null && quality == null) {
        return const ProfileNotice(
          key: ValueKey('user-voice-unavailable'),
          icon: Icons.mic_off_outlined,
          message: 'Voice is unavailable in this build.',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The devices answer what the machine has; the quality answers what
          // this machine sends its pictures at. Either can be missing without
          // taking the other with it.
          if (voice != null) VoiceDevicesSection(controller: voice),
          if (voice != null && quality != null) const SizedBox(height: 28),
          if (quality != null) StreamQualitySection(controller: quality),
        ],
      );
    }
    if (category == UserSettingsCategory.themes) {
      final themes = themeController;
      if (themes == null) {
        return const ProfileNotice(
          key: ValueKey('user-themes-unavailable'),
          icon: Icons.brush_outlined,
          message: 'Themes are unavailable in this build.',
        );
      }
      return ThemeSection(controller: themes);
    }
    // The safety hub is its own route too: an account with no settings store
    // still has a record, and gating this on settings would hide it.
    if (category == UserSettingsCategory.standing) {
      final standing = standingController;
      if (standing == null) {
        return const _NeedsAccountNotice(
          key: ValueKey('user-standing-unavailable'),
          toDo: 'see what is on its record',
        );
      }
      return AccountStandingSection(controller: standing);
    }
    // The family centre is its own route as well, for the same reason.
    if (category == UserSettingsCategory.family) {
      final family = familyController;
      if (family == null) {
        return const _NeedsAccountNotice(
          key: ValueKey('user-family-unavailable'),
          toDo: 'see its family centre',
        );
      }
      return FamilyCentreSection(controller: family);
    }
    if (category == UserSettingsCategory.devices) {
      final sessions = sessionController;
      if (sessions == null) {
        return const _NeedsAccountNotice(
          key: ValueKey('user-devices-unavailable'),
          toDo: 'see where it is signed in',
        );
      }
      return DevicesSettingsSection(controller: sessions);
    }

    // Connections, entitlements and app authorisation are their own routes
    // too, and answer for themselves rather than being gated on the
    // settings store.
    if (category == UserSettingsCategory.connections) {
      final connections = connectionsController;
      if (connections == null) {
        return const _NeedsAccountNotice(
          key: ValueKey('user-connections-unavailable'),
          toDo: 'link third-party accounts to it',
        );
      }
      return ConnectionsSettingsSection(controller: connections);
    }
    if (category == UserSettingsCategory.entitlements) {
      final entitlements = entitlementsController;
      if (entitlements == null) {
        return const _NeedsAccountNotice(
          key: ValueKey('user-entitlements-unavailable'),
          toDo: 'see what it holds',
        );
      }
      return EntitlementsSettingsSection(controller: entitlements);
    }
    if (category == UserSettingsCategory.apps) {
      final apps = appAuthorisationController;
      if (apps == null) {
        return const _NeedsAccountNotice(
          key: ValueKey('user-apps-unavailable'),
          toDo: 'authorise apps into servers it manages',
        );
      }
      return AppAuthorisationSection(controller: apps);
    }

    if (category == UserSettingsCategory.dataPackage) {
      final dataPackage = dataPackageController;
      if (dataPackage == null) {
        return const _NeedsAccountNotice(
          key: ValueKey('user-data-package-unavailable'),
          toDo: 'request its data',
        );
      }
      return DataPackageSettingsSection(controller: dataPackage);
    }
    if (category == UserSettingsCategory.security) {
      final mfa = mfaController;
      if (mfa == null) {
        return const _NeedsAccountNotice(
          key: ValueKey('user-mfa-unavailable'),
          toDo: 'manage two-factor authentication',
        );
      }
      return MfaSettingsSection(controller: mfa);
    }
    if (category == UserSettingsCategory.age) {
      final age = ageController;
      if (age == null) {
        return const _NeedsAccountNotice(
          key: ValueKey('user-age-unavailable'),
          toDo: 'see how it can prove its age',
        );
      }
      return AgeVerificationSection(controller: age);
    }
    if (!controller.isAvailable) {
      return const _NeedsAccountNotice(
        key: ValueKey('user-settings-unavailable'),
        toDo: 'read and change its settings',
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
          const ProfileNotice(
            icon: Icons.error_outline,
            message: 'Discord did not return your settings.',
          ),
          const SizedBox(height: 12),
          FlucordButton(
            kind: FlucordButtonKind.primary,
            label: 'Try again',
            onPressed: () => unawaited(controller.load()),
          ),
        ],
      );
    }
    return _section(settings);
  }

  Widget _section(UserSettings settings) => switch (category) {
    // Handled before the settings store is consulted.
    UserSettingsCategory.profile ||
    UserSettingsCategory.keybinds ||
    UserSettingsCategory.streamer ||
    UserSettingsCategory.accessibility ||
    UserSettingsCategory.themes ||
    UserSettingsCategory.voice => const SizedBox.shrink(),
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
    UserSettingsCategory.connections => const SizedBox.shrink(),
    UserSettingsCategory.entitlements => const SizedBox.shrink(),
    UserSettingsCategory.security => const SizedBox.shrink(),
    UserSettingsCategory.age => const SizedBox.shrink(),
    UserSettingsCategory.apps => const SizedBox.shrink(),
    UserSettingsCategory.dataPackage => const SizedBox.shrink(),
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

/// What a pane that needs a Discord account shows in demo mode and on a bot
/// account: what connecting one would let the person do, and why it is not
/// here now.
class _NeedsAccountNotice extends StatelessWidget {
  const _NeedsAccountNotice({required this.toDo, super.key});

  /// What the person could do with an account, as in "edit its profile".
  final String toDo;

  @override
  Widget build(BuildContext context) => ProfileNotice(
    icon: Icons.cloud_off_outlined,
    message:
        'Connect a Discord account to $toDo. Demo mode and bot accounts have '
        'no account behind them.',
  );
}
