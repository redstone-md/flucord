import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';

import '../../application/user_profile_controller.dart';
import '../../data/discord/discord_cdn.dart';
import '../../domain/chat_models.dart';
import '../../domain/user_profile.dart';
import '../../theme/flucord_type.dart';
import '../profile_image_picker.dart';
import 'profile_card.dart';
import 'profile_card_data.dart';
import 'user_profile_controls.dart';

/// The account's own profile, as Discord's "Profiles" screen edits it.
///
/// Unlike every other settings section this one does not save as you type: a
/// profile write is a single PATCH the server normalises and can reject, so the
/// form collects a draft and commits it once. That is also why the save bar
/// only appears when something is actually different.
///
/// Beside the form, [ProfileCard.preview] draws the draft the way other people
/// will see it once it is saved.
class UserProfileSection extends StatefulWidget {
  const UserProfileSection({
    required this.controller,
    this.imagePicker = const NativeProfileImagePicker(),
    this.presence,
    super.key,
  });

  final UserProfileController controller;
  final ProfileImagePicker imagePicker;

  /// The account's status for the preview's dot. Null draws no dot.
  final UserPresence? presence;

  @override
  State<UserProfileSection> createState() => _UserProfileSectionState();
}

class _UserProfileSectionState extends State<UserProfileSection> {
  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _bio = TextEditingController();
  final TextEditingController _pronouns = TextEditingController();
  String? _pickerError;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncFields);
    _syncFields();
    // Deferred by a microtask because the load notifies synchronously before
    // its first await: doing it here would rebuild the listener above this
    // widget while that listener is still building it.
    scheduleMicrotask(() {
      if (mounted) unawaited(widget.controller.load());
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFields);
    _displayName.dispose();
    _bio.dispose();
    _pronouns.dispose();
    super.dispose();
  }

  /// Pushes controller values into the fields without moving the caret.
  ///
  /// A dispatch from another device, a discard, and the echo after a save all
  /// change the value under a field the user may be sitting in. Writing only
  /// when the text actually differs is what stops the cursor from jumping to
  /// the end on every unrelated notification.
  void _syncFields() {
    _apply(_displayName, widget.controller.displayName);
    _apply(_bio, widget.controller.bio);
    _apply(_pronouns, widget.controller.pronouns);
  }

  static void _apply(TextEditingController field, String value) {
    if (field.text == value) return;
    field.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.isSupported) {
      return const ProfileNotice(
        key: ValueKey('user-profile-unavailable'),
        icon: FlucordIcons.offline,
        message:
            'Connect a Discord account to edit its profile. The demo and bot '
            'transports have no profile behind them.',
      );
    }
    final profile = controller.profile;
    if (profile == null) {
      return controller.isLoading
          ? const Center(
              key: ValueKey('user-profile-loading'),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Column(
              key: const ValueKey('user-profile-error'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ProfileNotice(
                  icon: FlucordIcons.error,
                  message: 'Discord did not return your profile.',
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey('user-profile-retry'),
                  onPressed: () => unawaited(controller.load()),
                  child: const Text('Try again'),
                ),
              ],
            );
    }
    final avatarUrl = _image(
      controller.pendingAvatar,
      () => DiscordCdn.userAvatar(profile.userId, profile.avatarHash),
    );
    final preview = ProfileCardData.ownProfile(
      profile,
      displayName: controller.displayName,
      pronouns: controller.pronouns,
      bio: controller.bio,
      accentColor: controller.accentColor,
      themeColors: controller.themeColors,
      avatarUrl: avatarUrl,
      bannerUrl: _image(
        controller.pendingBanner,
        () => DiscordCdn.userBanner(profile.userId, profile.bannerHash),
      ),
      presence: widget.presence,
    );
    return Column(
      key: const ValueKey('settings-section-profile'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ProfilePreviewHeader(title: 'Profile'),
        ProfileFormWithPreview(
          form: _form(context, profile, avatarUrl, preview.monogram),
          preview: ProfileCard.preview(data: preview),
        ),
      ],
    );
  }

  Widget _form(
    BuildContext context,
    UserProfile profile,
    String? avatarUrl,
    String monogram,
  ) {
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileAvatarRow(
          url: avatarUrl,
          monogram: monogram,
          onPick: () => _pick(controller.editAvatar),
          onRemove: profile.avatarHash == null
              ? null
              : () => controller.editAvatar(null),
        ),
        const SizedBox(height: 16),
        ProfileImageButtons(
          label: 'banner',
          onPick: () => _pick(controller.editBanner),
          onRemove: profile.bannerHash == null
              ? null
              : () => controller.editBanner(null),
        ),
        if (_pickerError case final message?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              message,
              key: const ValueKey('user-profile-picker-error'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: FlucordType.caption,
              ),
            ),
          ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ProfileField(
                label: 'Display name',
                hint: profile.username,
                helper:
                    'Shown instead of your username. Leave empty to use it.',
                maxLength: 32,
                controller: _displayName,
                fieldKey: const ValueKey('profile-display-name'),
                onChanged: controller.editDisplayName,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ProfileField(
                label: 'Pronouns',
                hint: 'Add your pronouns',
                maxLength: 40,
                controller: _pronouns,
                fieldKey: const ValueKey('profile-pronouns'),
                onChanged: controller.editPronouns,
              ),
            ),
          ],
        ),
        ProfileField(
          label: 'About me',
          helper: 'Markdown and links are supported.',
          maxLength: 190,
          maxLines: 4,
          controller: _bio,
          fieldKey: const ValueKey('profile-bio'),
          onChanged: controller.editBio,
        ),
        const SizedBox(height: 4),
        ProfileColourPicker(
          label: 'Accent colour',
          keyPrefix: 'profile-accent',
          value: controller.accentColor,
          onChanged: controller.editAccentColor,
        ),
        const SizedBox(height: 12),
        ..._themePickers(),
        const SizedBox(height: 8),
        ProfileIdentityFacts(profile: profile),
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Discord did not accept those changes.',
              key: const ValueKey('user-profile-save-error'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: FlucordType.caption,
              ),
            ),
          ),
        if (controller.hasChanges)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ProfileSaveBar(
              isSaving: controller.isSaving,
              onDiscard: () {
                setState(() => _pickerError = null);
                controller.discard();
              },
              onSave: () => unawaited(controller.save()),
            ),
          ),
      ],
    );
  }

  /// The theme's primary and accent. Discord takes both or neither, so the
  /// first pick fills both and "none" on either removes the theme.
  List<Widget> _themePickers() {
    final controller = widget.controller;
    final theme = controller.themeColors;
    void edit(int? colour, ProfileThemeColors Function(int) withColour) =>
        controller.editThemeColors(colour == null ? null : withColour(colour));
    return [
      ProfileColourPicker(
        label: 'Theme primary colour',
        keyPrefix: 'profile-theme-primary',
        value: theme?.primary,
        onChanged: (colour) => edit(
          colour,
          (primary) => ProfileThemeColors(primary, theme?.accent ?? primary),
        ),
      ),
      const SizedBox(height: 12),
      ProfileColourPicker(
        label: 'Theme accent colour',
        keyPrefix: 'profile-theme-accent',
        value: theme?.accent,
        onChanged: (colour) => edit(
          colour,
          (accent) => ProfileThemeColors(theme?.primary ?? accent, accent),
        ),
      ),
    ];
  }

  Future<void> _pick(void Function(String dataUri) stage) async {
    setState(() => _pickerError = null);
    try {
      final selection = await widget.imagePicker.pick();
      if (selection != null) stage(selection.dataUri);
    } on ProfileImageRejected catch (rejection) {
      if (mounted) setState(() => _pickerError = rejection.message);
    } on Object catch (_) {
      if (mounted) {
        setState(() => _pickerError = 'That image could not be read.');
      }
    }
  }

  /// A staged data URI wins over the stored hash, so the preview shows what is
  /// about to be saved rather than what is still on the account.
  static String? _image(ProfileImage pending, String? Function() stored) {
    if (pending.isUntouched) return stored();
    return pending.dataUri;
  }
}
