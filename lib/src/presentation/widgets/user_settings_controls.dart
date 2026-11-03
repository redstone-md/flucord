import 'package:flutter/material.dart';

import '../../domain/user_settings.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_controls.dart';

/// Heading for one group of settings rows, in the heading role.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: FlucordTextRole.heading.style.copyWith(
            color: context.surfaces.text,
          ),
        ),
        if (subtitle case final text?) ...[
          const SizedBox(height: 2),
          Text(
            text,
            style: FlucordTextRole.caption.style.copyWith(
              color: context.surfaces.muted,
            ),
          ),
        ],
      ],
    ),
  );
}

/// One settings row: what it is, how far it reaches, and its control.
///
/// The support verdict is rendered next to the control rather than buried in
/// a tooltip, because the whole point of showing a setting Flucord cannot
/// honour is that the user learns it will not do anything here.
class SettingRow extends StatelessWidget {
  const SettingRow({
    required this.title,
    required this.support,
    required this.child,
    this.description,
    this.note,
    super.key,
  });

  /// Below this width the control drops under the label instead of fighting
  /// it for horizontal room.
  static const stackedWidth = 460.0;

  final String title;
  final String? description;
  final UserSettingSupport support;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: FlucordTextRole.label.style.copyWith(
            fontWeight: FontWeight.w500,
            color: context.surfaces.text,
          ),
        ),
        if (description case final text?) ...[
          const SizedBox(height: 2),
          Text(
            text,
            style: FlucordTextRole.caption.style.copyWith(
              color: context.surfaces.muted,
            ),
          ),
        ],
        if (_verdict case final text?) ...[
          const SizedBox(height: 4),
          _SupportBadge(support: support, text: text),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < stackedWidth
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, const SizedBox(height: 8), child],
              )
            : Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 16),
                  Flexible(child: child),
                ],
              ),
      ),
    );
  }

  String? get _verdict => switch (support) {
    UserSettingSupport.applied => note,
    UserSettingSupport.accountOnly =>
      note ?? 'Saved to your Discord account. Flucord does not act on it.',
    UserSettingSupport.unavailable =>
      note ?? 'Flucord has no screen for this setting yet.',
  };
}

class _SupportBadge extends StatelessWidget {
  const _SupportBadge({required this.support, required this.text});

  final UserSettingSupport support;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = switch (support) {
      UserSettingSupport.applied => context.surfaces.success,
      UserSettingSupport.accountOnly => context.surfaces.link,
      UserSettingSupport.unavailable => context.surfaces.muted,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: FlucordIcon(
            support == UserSettingSupport.unavailable
                ? FlucordIcons.block
                : FlucordIcons.info,
            size: 12,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: FlucordTextRole.caption.style.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// A two-state control.
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    required this.value,
    required ValueChanged<bool> this.onChanged,
    super.key,
  });

  /// Shows the stored value without letting it be changed.
  ///
  /// A separate constructor rather than an `enabled` flag: a caller that
  /// cannot honour a setting has no handler to offer, and inventing an empty
  /// one to satisfy the signature is how a control ends up looking live.
  const SettingSwitch.readOnly({required this.value, super.key})
    : onChanged = null;

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: FlucordToggle(value: value, onChanged: onChanged),
  );
}

/// One option in a [SettingChoices] row.
final class SettingChoice<T extends Enum> {
  const SettingChoice(this.value, this.label, {this.enabled = true});

  final T value;
  final String label;

  /// A choice Discord stores but Flucord cannot honour stays visible and
  /// unselectable: hiding it would misrepresent what the account can hold.
  final bool enabled;
}

/// A segmented group, one option per choice.
///
/// The group wraps rather than overflowing, which keeps the settings pane
/// usable in a narrow window.
class SettingChoices<T extends Enum> extends StatelessWidget {
  const SettingChoices({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.keyPrefix,
    super.key,
  });

  final List<SettingChoice<T>> options;
  final T? selected;
  final ValueChanged<T> onSelected;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: FlucordSegmented<T>(
      keyPrefix: keyPrefix,
      options: [
        for (final option in options)
          FlucordSegment(option.value, option.label, enabled: option.enabled),
      ],
      selected: selected,
      onSelected: onSelected,
    ),
  );
}

/// A value Flucord can show but not change.
class SettingValue extends StatelessWidget {
  const SettingValue(this.value, {super.key});

  final String value;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        borderRadius: FlucordRadius.control,
        border: Border.all(color: context.surfaces.border),
      ),
      child: Text(
        value,
        style: FlucordTextRole.label.style.copyWith(
          color: context.surfaces.muted,
        ),
      ),
    ),
  );
}
