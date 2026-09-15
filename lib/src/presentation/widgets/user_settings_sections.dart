import 'package:flutter/material.dart';

import '../../domain/user_settings.dart';
import '../../domain/user_settings_repository.dart';
import 'user_settings_controls.dart';

/// Signature the sections use to hand an edit back to the controller.
typedef UserSettingsEdit = void Function(UserSettingsPatch patch);

/// Appearance and theme, `PreloadedUserSettings.appearance`.
class AppearanceSettingsSection extends StatelessWidget {
  const AppearanceSettingsSection({
    required this.settings,
    required this.onEdit,
    super.key,
  });

  final UserSettings settings;
  final UserSettingsEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final appearance = settings.appearance;
    return Column(
      key: const ValueKey('settings-section-appearance'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Appearance',
          subtitle: 'How Flucord draws your account.',
        ),
        SettingRow(
          title: 'Theme',
          description: 'The palette every surface is built from.',
          support: UserSettingSupport.applied,
          note: appearance.theme.isRenderable
              ? null
              : 'Flucord ships Dark and Light only, so the other two cannot '
                    'be chosen here.',
          child: SettingChoices<UserSettingsTheme>(
            keyPrefix: 'setting-theme',
            selected: appearance.theme,
            onSelected: (theme) => onEdit(UserSettingsPatch(theme: theme)),
            options: const [
              SettingChoice(UserSettingsTheme.dark, 'Dark'),
              SettingChoice(UserSettingsTheme.light, 'Light'),
              SettingChoice(UserSettingsTheme.darker, 'Darker', enabled: false),
              SettingChoice(
                UserSettingsTheme.midnight,
                'Midnight',
                enabled: false,
              ),
            ],
          ),
        ),
        SettingRow(
          title: 'Time format',
          description: 'The clock shown beside every message.',
          support: UserSettingSupport.applied,
          child: SettingChoices<TimestampHourCycle>(
            keyPrefix: 'setting-hour-cycle',
            selected: appearance.timestampHourCycle,
            onSelected: (cycle) =>
                onEdit(UserSettingsPatch(timestampHourCycle: cycle)),
            options: const [
              SettingChoice(TimestampHourCycle.auto, 'Automatic'),
              SettingChoice(TimestampHourCycle.hour12, '12-hour'),
              SettingChoice(TimestampHourCycle.hour23, '24-hour'),
            ],
          ),
        ),
        SettingRow(
          title: 'Developer mode',
          description: 'Discord\'s copy-id menus.',
          support: UserSettingSupport.unavailable,
          child: SettingSwitch.readOnly(
            key: const ValueKey('setting-developer-mode'),
            value: appearance.developerMode,
          ),
        ),
        SettingRow(
          title: 'Display density',
          description: 'How tightly the message list packs its rows.',
          support: UserSettingSupport.applied,
          child: SettingChoices<UserInterfaceDensity>(
            keyPrefix: 'setting-density',
            selected: appearance.density,
            onSelected: (density) =>
                onEdit(UserSettingsPatch(density: density)),
            options: const [
              SettingChoice(UserInterfaceDensity.compact, 'Compact'),
              SettingChoice(UserInterfaceDensity.cozy, 'Cozy'),
              // The two Discord also lists, which this client draws the same
              // way it draws cozy: the account keeps them for the client
              // that distinguishes them.
              SettingChoice(UserInterfaceDensity.responsive, 'Responsive'),
              SettingChoice(UserInterfaceDensity.standard, 'Default'),
            ],
          ),
        ),
        SettingRow(
          title: 'Dark sidebar',
          description:
              'The channel list keeps the dark rail in the light '
              'theme.',
          support: UserSettingSupport.applied,
          child: SettingSwitch(
            key: const ValueKey('setting-dark-sidebar'),
            value: appearance.darkSidebar,
            onChanged: (value) => onEdit(UserSettingsPatch(darkSidebar: value)),
          ),
        ),
      ],
    );
  }
}

/// Message display, from `PreloadedUserSettings.text_and_images`.
class ChatSettingsSection extends StatelessWidget {
  const ChatSettingsSection({
    required this.settings,
    required this.onEdit,
    super.key,
  });

  final UserSettings settings;
  final UserSettingsEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final display = settings.messageDisplay;
    return Column(
      key: const ValueKey('settings-section-chat'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Chat',
          subtitle: 'What a message shows once it arrives.',
        ),
        SettingRow(
          title: 'Show link previews',
          description: 'Embeds Discord builds for links and bot messages.',
          support: UserSettingSupport.applied,
          child: SettingSwitch(
            key: const ValueKey('setting-render-embeds'),
            value: display.rendersEmbeds,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(renderEmbeds: value)),
          ),
        ),
        SettingRow(
          title: 'Show images in link previews',
          support: UserSettingSupport.applied,
          child: SettingSwitch(
            key: const ValueKey('setting-inline-embed-media'),
            value: display.rendersEmbedMedia,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(inlineEmbedMedia: value)),
          ),
        ),
        SettingRow(
          title: 'Show attached images and video',
          support: UserSettingSupport.applied,
          child: SettingSwitch(
            key: const ValueKey('setting-inline-attachment-media'),
            value: display.rendersAttachmentMedia,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(inlineAttachmentMedia: value)),
          ),
        ),
        SettingRow(
          title: 'Show reactions',
          support: UserSettingSupport.applied,
          child: SettingSwitch(
            key: const ValueKey('setting-render-reactions'),
            value: display.rendersReactions,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(renderReactions: value)),
          ),
        ),
        SettingRow(
          title: 'Compact message layout',
          description: 'Discord\'s single-line alternative to cozy mode.',
          support: UserSettingSupport.unavailable,
          note: 'Flucord draws the cozy layout only.',
          child: SettingSwitch.readOnly(value: display.isCompact),
        ),
        SettingRow(
          title: 'Play animated emoji',
          description:
              'A still frame stands in for a custom emoji that '
              'moves.',
          support: UserSettingSupport.applied,
          child: SettingSwitch(
            key: const ValueKey('setting-animate-emoji'),
            value: display.playsAnimatedEmoji,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(animateEmoji: value)),
          ),
        ),
        SettingRow(
          title: 'Autoplay GIFs',
          description: 'Messages keep GIFs on their first frame.',
          support: UserSettingSupport.applied,
          child: SettingSwitch(
            key: const ValueKey('setting-gif-autoplay'),
            value: display.playsGifs,
            onChanged: (value) => onEdit(UserSettingsPatch(gifAutoPlay: value)),
          ),
        ),
        SettingRow(
          title: 'Convert emoticons to emoji',
          support: UserSettingSupport.unavailable,
          child: SettingSwitch.readOnly(
            value: display.convertEmoticons ?? true,
          ),
        ),
        SettingRow(
          title: 'Enable /tts',
          support: UserSettingSupport.applied,
          child: SettingSwitch(
            key: const ValueKey('setting-enable-tts'),
            value: display.enableTextToSpeechCommand ?? true,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(enableTextToSpeechCommand: value)),
          ),
        ),
      ],
    );
  }
}

/// `PreloadedUserSettings.notifications`.
class NotificationSettingsSection extends StatelessWidget {
  const NotificationSettingsSection({
    required this.settings,
    required this.onEdit,
    super.key,
  });

  final UserSettings settings;
  final UserSettingsEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final notifications = settings.notifications;
    return Column(
      key: const ValueKey('settings-section-notifications'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Notifications',
          subtitle: 'When your account is allowed to interrupt you.',
        ),
        SettingRow(
          title: 'Quiet mode',
          description: 'Silences desktop notifications everywhere.',
          support: UserSettingSupport.applied,
          child: SettingSwitch(
            key: const ValueKey('setting-quiet-mode'),
            value: notifications.isQuiet,
            onChanged: (value) => onEdit(UserSettingsPatch(quietMode: value)),
          ),
        ),
        SettingRow(
          title: 'Tell friends when you go live',
          support: UserSettingSupport.accountOnly,
          child: SettingSwitch(
            key: const ValueKey('setting-go-live-notifications'),
            value: notifications.notifiesFriendsOnGoLive,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(notifyFriendsOnGoLive: value)),
          ),
        ),
        SettingRow(
          title: 'Notify me when a friend comes online',
          support: UserSettingSupport.accountOnly,
          child: SettingSwitch(
            key: const ValueKey('setting-friend-online-notifications'),
            value: notifications.notifiesOnFriendOnline,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(friendOnlineNotifications: value)),
          ),
        ),
        SettingRow(
          title: 'Reaction notifications',
          support: UserSettingSupport.accountOnly,
          child: SettingChoices<ReactionNotifications>(
            keyPrefix: 'setting-reaction-notifications',
            selected: notifications.reactionNotifications,
            onSelected: (value) =>
                onEdit(UserSettingsPatch(reactionNotifications: value)),
            options: const [
              SettingChoice(ReactionNotifications.enabled, 'All'),
              SettingChoice(
                ReactionNotifications.onlyDirectMessages,
                'Direct messages',
              ),
              SettingChoice(ReactionNotifications.disabled, 'None'),
            ],
          ),
        ),
        SettingRow(
          title: 'In-app notifications',
          description: 'The toast a new message raises.',
          support: UserSettingSupport.applied,
          child: SettingSwitch(
            key: const ValueKey('setting-in-app-notifications'),
            value: notifications.showsInAppNotifications,
            onChanged: (value) =>
                onEdit(UserSettingsPatch(showInAppNotifications: value)),
          ),
        ),
      ],
    );
  }
}
