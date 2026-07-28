import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/user_profile_controller.dart';
import '../../data/discord/discord_cdn.dart';
import '../../domain/user_profile.dart';
import '../../theme/flucord_theme.dart';
import '../profile_image_picker.dart';
import 'remote_identity_image.dart';
import 'user_profile_controls.dart';

/// The account's own profile, as Discord's "Profiles" screen edits it.
///
/// Unlike every other settings section this one does not save as you type: a
/// profile write is a single PATCH the server normalises and can reject, so the
/// form collects a draft and commits it once. That is also why the save bar
/// only appears when something is actually different.
class UserProfileSection extends StatefulWidget {
  const UserProfileSection({
    required this.controller,
    this.imagePicker = const NativeProfileImagePicker(),
    super.key,
  });

  final UserProfileController controller;
  final ProfileImagePicker imagePicker;

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
        icon: Icons.cloud_off_outlined,
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
                  icon: Icons.error_outline,
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
    return Column(
      key: const ValueKey('settings-section-profile'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ProfilePreviewHeader(title: 'Profile'),
        ProfilePreviewCard(
          profile: profile,
          pendingAvatar: controller.pendingAvatar,
          pendingBanner: controller.pendingBanner,
          accentColor: controller.accentColor,
          displayName: controller.displayName,
          onPickAvatar: () => _pick(controller.editAvatar),
          onRemoveAvatar: profile.avatarHash == null
              ? null
              : () => controller.editAvatar(null),
          onPickBanner: () => _pick(controller.editBanner),
          onRemoveBanner: profile.bannerHash == null
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
                fontSize: 11,
              ),
            ),
          ),
        const SizedBox(height: 20),
        ProfileField(
          label: 'Display name',
          hint: profile.username,
          helper: 'Shown instead of your username. Leave empty to use it.',
          maxLength: 32,
          controller: _displayName,
          fieldKey: const ValueKey('profile-display-name'),
          onChanged: controller.editDisplayName,
        ),
        ProfileField(
          label: 'Pronouns',
          maxLength: 40,
          controller: _pronouns,
          fieldKey: const ValueKey('profile-pronouns'),
          onChanged: controller.editPronouns,
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
        ProfileAccentPicker(
          value: controller.accentColor,
          onChanged: controller.editAccentColor,
        ),
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
                fontSize: 12,
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
}

/// Avatar, banner and name, drawn the way other people will see them.
class ProfilePreviewCard extends StatelessWidget {
  const ProfilePreviewCard({
    required this.profile,
    required this.pendingAvatar,
    required this.pendingBanner,
    required this.accentColor,
    required this.displayName,
    required this.onPickAvatar,
    required this.onRemoveAvatar,
    required this.onPickBanner,
    required this.onRemoveBanner,
    super.key,
  });

  final UserProfile profile;
  final ProfileImage pendingAvatar;
  final ProfileImage pendingBanner;
  final int? accentColor;
  final String displayName;
  final VoidCallback onPickAvatar;
  final VoidCallback? onRemoveAvatar;
  final VoidCallback onPickBanner;
  final VoidCallback? onRemoveBanner;

  @override
  Widget build(BuildContext context) {
    final banner = _image(
      pendingBanner,
      () => DiscordCdn.userBanner(profile.userId, profile.bannerHash),
    );
    final avatar = _image(
      pendingAvatar,
      () => DiscordCdn.userAvatar(profile.userId, profile.avatarHash),
    );
    final accent = accentColor == null
        ? context.surfaces.raised
        : Color(0xff000000 | accentColor!);
    return Container(
      key: const ValueKey('profile-preview-card'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.surfaces.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 106,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RemoteIdentityImage(
                  url: banner,
                  fallback: ColoredBox(color: accent),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: ProfileImageActions(
                    label: 'banner',
                    onPick: onPickBanner,
                    onRemove: onRemoveBanner,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.translate(
                  offset: const Offset(0, -26),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ProfileAvatarButton(
                        url: avatar,
                        initial: profile.effectiveName,
                        onPick: onPickAvatar,
                        onRemove: onRemoveAvatar,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                displayName.isEmpty
                                    ? profile.username
                                    : displayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                profile.hasLegacyDiscriminator
                                    ? '${profile.username}#'
                                          '${profile.discriminator}'
                                    : profile.username,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.surfaces.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (profile.pronouns.isNotEmpty)
                  Transform.translate(
                    offset: const Offset(0, -18),
                    child: Text(
                      profile.pronouns,
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (profile.bio.isNotEmpty)
                  Transform.translate(
                    offset: const Offset(0, -12),
                    child: Text(
                      profile.bio,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A staged data URI wins over the stored hash, so the preview shows what is
  /// about to be saved rather than what is still on the account.
  static String? _image(ProfileImage pending, String? Function() stored) {
    if (pending.isUntouched) return stored();
    return pending.dataUri;
  }
}
