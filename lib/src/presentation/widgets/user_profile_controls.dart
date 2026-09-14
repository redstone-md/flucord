import 'package:flutter/material.dart';

import '../../domain/user_profile.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';

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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'How your account looks to everyone else. Changes are saved '
          'together.',
          style: TextStyle(color: context.surfaces.muted, fontSize: 12),
        ),
      ],
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
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: context.surfaces.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          key: fieldKey,
          controller: controller,
          onChanged: onChanged,
          maxLength: maxLength,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
            helperStyle: TextStyle(color: context.surfaces.muted, fontSize: 11),
            isDense: true,
            filled: true,
            fillColor: context.surfaces.canvas,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: context.surfaces.border),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The round avatar, with the controls that replace or clear it.
class ProfileAvatarButton extends StatelessWidget {
  const ProfileAvatarButton({
    required this.url,
    required this.initial,
    required this.onPick,
    required this.onRemove,
    super.key,
  });

  final String? url;
  final String initial;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Container(
        width: 76,
        height: 76,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.surfaces.canvas,
          border: Border.all(color: context.surfaces.raised, width: 5),
        ),
        child: RemoteIdentityImage(
          url: url,
          fallback: Center(
            child: Text(
              initial.isEmpty ? '?' : initial.characters.first.toUpperCase(),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
      Positioned(
        right: 0,
        bottom: 0,
        child: ProfileImageActions(
          label: 'avatar',
          compact: true,
          onPick: onPick,
          onRemove: onRemove,
        ),
      ),
    ],
  );
}

/// Replace and remove, for one image.
class ProfileImageActions extends StatelessWidget {
  const ProfileImageActions({
    required this.label,
    required this.onPick,
    required this.onRemove,
    this.compact = false,
    super.key,
  });

  final String label;
  final VoidCallback onPick;

  /// Null when there is nothing stored to remove.
  final VoidCallback? onRemove;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Button(
        buttonKey: ValueKey('profile-pick-$label'),
        tooltip: 'Change $label',
        icon: Icons.edit_outlined,
        compact: compact,
        onPressed: onPick,
      ),
      if (onRemove != null) ...[
        const SizedBox(width: 4),
        _Button(
          buttonKey: ValueKey('profile-remove-$label'),
          tooltip: 'Remove $label',
          icon: Icons.close,
          compact: compact,
          onPressed: onRemove!,
        ),
      ],
    ],
  );
}

class _Button extends StatelessWidget {
  const _Button({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.compact,
    required this.onPressed,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 24.0 : 28.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          key: buttonKey,
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: compact ? 13 : 15, color: Colors.white),
          ),
        ),
      ),
    );
  }
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
      Text(
        'ACCENT COLOUR',
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Swatch(
            swatchKey: const ValueKey('profile-accent-none'),
            selected: value == null,
            onPressed: () => onChanged(null),
            child: Icon(
              Icons.format_color_reset_outlined,
              size: 15,
              color: context.surfaces.muted,
            ),
          ),
          for (final swatch in profileAccentSwatches)
            _Swatch(
              swatchKey: ValueKey('profile-accent-${swatch.toRadixString(16)}'),
              selected: value == swatch,
              colour: Color(0xff000000 | swatch),
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
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(
        color: selected
            ? Theme.of(context).colorScheme.onSurface
            : context.surfaces.border,
        width: selected ? 2 : 1,
      ),
    ),
    child: InkWell(
      key: swatchKey,
      borderRadius: BorderRadius.circular(6),
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
      borderRadius: BorderRadius.circular(6),
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
          style: TextStyle(color: context.surfaces.muted, fontSize: 11),
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
            style: TextStyle(color: context.surfaces.muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontSize: 12)),
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
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: context.surfaces.border),
    ),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Careful — you have unsaved changes.',
            style: TextStyle(fontSize: 12),
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
