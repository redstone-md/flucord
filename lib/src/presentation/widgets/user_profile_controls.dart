import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';

import '../../domain/discord_rgb.dart';
import '../../domain/user_profile.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_button.dart';
import 'flucord_controls.dart';
import 'profile_card.dart';
import 'user_settings_controls.dart';

/// Discord's accent swatches, plus "no accent" which falls back to the avatar.
const profileAccentSwatches = <int>[
  0x5865f2,
  0x57f287,
  0xfee75c,
  0xeb459e,
  0xed4245,
  0xf47b67,
  0x9b59b6,
  0x1abc9c,
  0x3498db,
  0x2c2f33,
];

class ProfilePreviewHeader extends StatelessWidget {
  const ProfilePreviewHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SettingsSectionHeader(
      title: title,
      subtitle:
          'How your account looks to everyone else. Changes are saved '
          'together.',
    ),
  );
}

/// One labelled text field in the profile form.
class ProfileField extends StatelessWidget {
  const ProfileField({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.fieldKey,
    this.hint,
    this.helper,
    this.maxLength,
    this.maxLines = 1,
    super.key,
  });

  final String label;
  final String? hint;
  final String? helper;
  final int? maxLength;
  final int maxLines;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlucordFieldLabel(label),
        TextField(
          key: fieldKey,
          controller: controller,
          onChanged: onChanged,
          maxLength: maxLength,
          maxLines: maxLines,
          style: const TextStyle(fontSize: FlucordType.label),
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
            helperStyle: TextStyle(
              color: context.surfaces.muted,
              fontSize: FlucordType.caption,
            ),
            isDense: true,
            filled: true,
            fillColor: context.surfaces.canvas,
            border: OutlineInputBorder(
              borderRadius: FlucordRadius.small,
              borderSide: BorderSide(color: context.surfaces.border),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The form on the left and the live preview in a 300 px column on the
/// right. Where the two do not fit side by side, the preview goes under the
/// form.
class ProfileFormWithPreview extends StatelessWidget {
  const ProfileFormWithPreview({
    required this.form,
    required this.preview,
    super.key,
  });

  /// The narrowest width that still fits the form beside the preview.
  static const besideWidth = 680.0;
  static const _gap = 32.0;

  final Widget form;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      key: const ValueKey('profile-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview',
          style: FlucordTextRole.caption.style.copyWith(
            color: context.surfaces.captionText,
          ),
        ),
        const SizedBox(height: 8),
        preview,
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < besideWidth
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [form, const SizedBox(height: _gap), column],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: form),
                const SizedBox(width: _gap),
                SizedBox(width: ProfileCard.width, child: column),
              ],
            ),
    );
  }
}

/// The avatar as it is now, with the buttons that replace or remove it.
class ProfileAvatarRow extends StatelessWidget {
  const ProfileAvatarRow({
    required this.url,
    required this.monogram,
    required this.onPick,
    required this.onRemove,
    super.key,
  });

  static const _size = 80.0;

  final String? url;

  /// What stands in where there is no avatar.
  final String monogram;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipOval(
        child: SizedBox.square(
          dimension: _size,
          child: ProfileAvatarImage(url: url, monogram: monogram),
        ),
      ),
      const SizedBox(width: 16),
      ProfileImageButtons(label: 'avatar', onPick: onPick, onRemove: onRemove),
    ],
  );
}

/// "Change" and "Remove" for one profile image.
class ProfileImageButtons extends StatelessWidget {
  const ProfileImageButtons({
    required this.label,
    required this.onPick,
    required this.onRemove,
    super.key,
  });

  final String label;
  final VoidCallback onPick;

  /// Null when there is nothing stored to remove.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FlucordButton(
        key: ValueKey('profile-pick-$label'),
        label: 'Change $label',
        onPressed: onPick,
      ),
      if (onRemove case final remove?)
        FlucordButton(
          key: ValueKey('profile-remove-$label'),
          label: 'Remove $label',
          kind: FlucordButtonKind.ghost,
          onPressed: remove,
        ),
    ],
  );
}

/// The banner colour behind the profile, or none at all.
class ProfileAccentPicker extends StatelessWidget {
  const ProfileAccentPicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The 24-bit RGB accent, or `null` for the avatar's own colour.
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const FlucordFieldLabel('Accent colour'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Swatch(
            swatchKey: const ValueKey('profile-accent-none'),
            selected: value == null,
            onPressed: () => onChanged(null),
            child: FlucordIcon(
              FlucordIcons.noColour,
              size: 15,
              color: context.surfaces.muted,
            ),
          ),
          for (final swatch in profileAccentSwatches)
            _Swatch(
              swatchKey: ValueKey('profile-accent-${swatch.toRadixString(16)}'),
              selected: value == swatch,
              colour: Color(DiscordRgb(swatch).opaque),
              onPressed: () => onChanged(swatch),
            ),
        ],
      ),
    ],
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.swatchKey,
    required this.selected,
    required this.onPressed,
    this.colour,
    this.child,
  });

  final Key swatchKey;
  final bool selected;
  final VoidCallback onPressed;
  final Color? colour;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Material(
    color: colour ?? context.surfaces.canvas,
    shape: RoundedRectangleBorder(
      borderRadius: FlucordRadius.medium,
      side: BorderSide(
        color: selected
            ? Theme.of(context).colorScheme.onSurface
            : context.surfaces.border,
        width: selected ? 2 : 1,
      ),
    ),
    child: InkWell(
      key: swatchKey,
      borderRadius: FlucordRadius.medium,
      onTap: onPressed,
      child: SizedBox(width: 30, height: 30, child: Center(child: child)),
    ),
  );
}

/// The parts of an identity this screen shows but cannot change here.
///
/// Changing a username is password-gated and lives behind its own flow, so it
/// is stated rather than offered: a field that silently could not be saved
/// would be worse than none.
class ProfileIdentityFacts extends StatelessWidget {
  const ProfileIdentityFacts({required this.profile, super.key});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('profile-identity-facts'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.surfaces.raised,
      borderRadius: FlucordRadius.medium,
      border: Border.all(color: context.surfaces.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Fact(label: 'Username', value: profile.username),
        if (profile.hasLegacyDiscriminator)
          _Fact(label: 'Tag', value: '#${profile.discriminator}'),
        _Fact(label: 'User ID', value: profile.userId),
        const SizedBox(height: 6),
        Text(
          'Your username and password are changed in Discord itself: both '
          'need a password confirmation Flucord does not ask for.',
          style: TextStyle(
            color: context.surfaces.muted,
            fontSize: FlucordType.caption,
          ),
        ),
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyle(
              color: context.surfaces.muted,
              fontSize: FlucordType.caption,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: FlucordType.caption),
          ),
        ),
      ],
    ),
  );
}

/// Save or throw away the pending edit.
class ProfileSaveBar extends StatelessWidget {
  const ProfileSaveBar({
    required this.isSaving,
    required this.onDiscard,
    required this.onSave,
    super.key,
  });

  final bool isSaving;
  final VoidCallback onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('profile-save-bar'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: context.surfaces.raised,
      borderRadius: FlucordRadius.medium,
      border: Border.all(color: context.surfaces.border),
    ),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Careful — you have unsaved changes.',
            style: TextStyle(fontSize: FlucordType.caption),
          ),
        ),
        TextButton(
          key: const ValueKey('profile-discard'),
          onPressed: isSaving ? null : onDiscard,
          child: const Text('Reset'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('profile-save'),
          onPressed: isSaving ? null : onSave,
          child: Text(isSaving ? 'Saving…' : 'Save changes'),
        ),
      ],
    ),
  );
}

/// A short explanation where a form would otherwise be.
class ProfileNotice extends StatelessWidget {
  const ProfileNotice({required this.icon, required this.message, super.key});

  final FlucordIconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FlucordIcon(icon, size: 18, color: context.surfaces.muted),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          message,
          style: TextStyle(
            color: context.surfaces.muted,
            fontSize: FlucordType.caption,
          ),
        ),
      ),
    ],
  );
}
