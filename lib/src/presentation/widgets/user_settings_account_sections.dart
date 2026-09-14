import 'package:flutter/material.dart';

import '../../domain/user_settings.dart';
import '../../domain/user_settings_repository.dart';
import '../../theme/flucord_theme.dart';
import 'user_settings_controls.dart';
import 'user_settings_sections.dart';

/// `PreloadedUserSettings.privacy`, plus the two content filters Discord keeps
/// in the text group but shows on this screen.
class PrivacySettingsSection extends StatelessWidget {
  const PrivacySettingsSection({
    required this.settings,
    required this.onEdit,
    super.key,
  });

  final UserSettings settings;
  final UserSettingsEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final privacy = settings.privacy;
    return Column(
      key: const ValueKey('settings-section-privacy'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Privacy',
          subtitle: 'What your account shares, and with whom.',
        ),
        SettingRow(
          title: 'Let friends join your activity',
          support: UserSettingSupport.accountOnly,
          child: SettingSwitch(
            key: const ValueKey('setting-activity-party-friends'),
            value: privacy.allowsActivityPartyFriends,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(allowActivityPartyFriends: value)),
          ),
        ),
        SettingRow(
          title: 'Let people in your voice channel join your activity',
          support: UserSettingSupport.accountOnly,
          child: SettingSwitch(
            key: const ValueKey('setting-activity-party-voice'),
            value: privacy.allowsActivityPartyVoiceChannel,
            onChanged: (value) => onEdit(
              UserSettingsPatch(allowActivityPartyVoiceChannel: value),
            ),
          ),
        ),
        SettingRow(
          title: 'Detect accounts on this device',
          description: 'Games and platforms Discord may link automatically.',
          support: UserSettingSupport.accountOnly,
          child: SettingSwitch(
            key: const ValueKey('setting-detect-platform-accounts'),
            value: privacy.detectsPlatformAccounts,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(detectPlatformAccounts: value)),
          ),
        ),
        SettingRow(
          title: 'Show your local time on your profile',
          support: UserSettingSupport.accountOnly,
          child: SettingSwitch(
            key: const ValueKey('setting-show-local-time'),
            value: privacy.showsLocalTime,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(showLocalTime: value)),
          ),
        ),
        SettingRow(
          title: 'Hide your legacy username',
          support: UserSettingSupport.accountOnly,
          child: SettingSwitch(
            key: const ValueKey('setting-hide-legacy-username'),
            value: privacy.hidesLegacyUsername,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(hideLegacyUsername: value)),
          ),
        ),
        SettingRow(
          title: 'Filter direct messages for spam',
          support: UserSettingSupport.accountOnly,
          child: SettingChoices<DirectMessageSpamFilter>(
            keyPrefix: 'setting-spam-filter',
            selected: settings.messageDisplay.spamFilter,
            onSelected: (value) => onEdit(UserSettingsPatch(spamFilter: value)),
            options: const [
              SettingChoice(DirectMessageSpamFilter.defaultUnset, 'Default'),
              SettingChoice(DirectMessageSpamFilter.disabled, 'Off'),
              SettingChoice(DirectMessageSpamFilter.nonFriends, 'Non-friends'),
              SettingChoice(
                DirectMessageSpamFilter.friendsAndNonFriends,
                'Everyone',
              ),
            ],
          ),
        ),
        SettingRow(
          title: 'New servers can see my activity',
          support: UserSettingSupport.unavailable,
          note: 'Read-only: Discord splits this across several stored fields.',
          child: SettingSwitch.readOnly(
            value: !privacy.defaultGuildsRestricted,
          ),
        ),
      ],
    );
  }
}

/// `PreloadedUserSettings.localization`.
class LanguageSettingsSection extends StatelessWidget {
  const LanguageSettingsSection({required this.settings, super.key});

  final UserSettings settings;

  @override
  Widget build(BuildContext context) {
    final localization = settings.localization;
    final offset = localization.timezoneOffsetMinutes;
    return Column(
      key: const ValueKey('settings-section-language'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Language',
          subtitle: 'The locale your account is set to.',
        ),
        SettingRow(
          title: 'Language',
          support: UserSettingSupport.unavailable,
          note: 'Flucord ships English strings only.',
          child: SettingValue(_orUnset(localization.locale)),
        ),
        SettingRow(
          title: 'Time zone',
          support: UserSettingSupport.unavailable,
          child: SettingValue(_orUnset(localization.timezoneName)),
        ),
        SettingRow(
          title: 'Time zone offset',
          support: UserSettingSupport.unavailable,
          child: SettingValue(
            offset == null ? 'Not set' : '$offset minutes from UTC',
          ),
        ),
      ],
    );
  }

  static String _orUnset(String? value) =>
      value == null || value.isEmpty ? 'Not set' : value;
}

/// `PreloadedUserSettings.status`.
class StatusSettingsSection extends StatefulWidget {
  const StatusSettingsSection({
    required this.settings,
    required this.onEdit,
    super.key,
  });

  final UserSettings settings;
  final UserSettingsEdit onEdit;

  @override
  State<StatusSettingsSection> createState() => _StatusSettingsSectionState();
}

class _StatusSettingsSectionState extends State<StatusSettingsSection> {
  late final TextEditingController _custom = TextEditingController(
    text: widget.settings.status.customStatusText ?? '',
  );

  @override
  void didUpdateWidget(covariant StatusSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.settings.status.customStatusText ?? '';
    // An edit from another device should land in the field, but not while the
    // user is halfway through typing over it.
    if (incoming != (oldWidget.settings.status.customStatusText ?? '') &&
        incoming != _custom.text) {
      _custom.text = incoming;
    }
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.settings.status;
    return Column(
      key: const ValueKey('settings-section-status'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Status',
          subtitle: 'The presence your account carries between clients.',
        ),
        SettingRow(
          title: 'Online status',
          support: UserSettingSupport.unavailable,
          note: 'Flucord does not broadcast presence yet.',
          child: SettingValue(
            status.status == null || status.status!.isEmpty
                ? 'Not set'
                : status.status!,
          ),
        ),
        SettingRow(
          title: 'Custom status',
          description: 'The message shown under your name.',
          support: UserSettingSupport.accountOnly,
          child: _CustomStatusField(
            controller: _custom,
            onSave: (text) =>
                widget.onEdit(UserSettingsPatch(customStatusText: text)),
            onClear: () {
              _custom.clear();
              widget.onEdit(const UserSettingsPatch(clearCustomStatus: true));
            },
          ),
        ),
        if (status.customStatusEmojiName case final emoji?)
          if (emoji.isNotEmpty)
            SettingRow(
              title: 'Custom status emoji',
              support: UserSettingSupport.unavailable,
              child: SettingValue(emoji),
            ),
        SettingRow(
          title: 'Show the game you are playing',
          support: UserSettingSupport.accountOnly,
          child: SettingSwitch(
            key: const ValueKey('setting-show-current-game'),
            value: status.showsCurrentGame,
            onChanged: (value) =>
                widget.onEdit(UserSettingsPatch(showCurrentGame: value)),
          ),
        ),
        if (status.statusExpiresAtMs > 0)
          SettingRow(
            title: 'Status expires',
            support: UserSettingSupport.unavailable,
            child: SettingValue(
              DateTime.fromMillisecondsSinceEpoch(
                status.statusExpiresAtMs,
                isUtc: true,
              ).toIso8601String(),
            ),
          ),
      ],
    );
  }
}

class _CustomStatusField extends StatelessWidget {
  const _CustomStatusField({
    required this.controller,
    required this.onSave,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSave;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 320),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('setting-custom-status-field'),
          controller: controller,
          maxLength: 128,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            counterStyle: TextStyle(color: context.surfaces.muted, fontSize: 9),
            hintText: "What's happening?",
          ),
          onSubmitted: onSave,
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              key: const ValueKey('setting-custom-status-clear'),
              onPressed: onClear,
              child: const Text('Clear'),
            ),
            FilledButton(
              key: const ValueKey('setting-custom-status-save'),
              onPressed: () => onSave(controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    ),
  );
}
