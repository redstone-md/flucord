import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// The label over a field or a select: label role, 500, muted, 6 px above.
class FlucordFieldLabel extends StatelessWidget {
  const FlucordFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: FlucordTextRole.label.style.copyWith(
        fontWeight: FontWeight.w500,
        color: context.surfaces.muted,
      ),
    ),
  );
}

/// A labelled text field. The recessed look, the focus ring and the error
/// border come from the theme's input decoration.
///
/// [multiline] makes an 88 px box with the text at its top.
class FlucordTextField extends StatelessWidget {
  const FlucordTextField({
    this.label,
    this.controller,
    this.hintText,
    this.errorText,
    this.multiline = false,
    this.maxLength,
    this.autofocus = false,
    this.enabled = true,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.fieldKey,
    super.key,
  });

  static const _multilineHeight = 88.0;

  final String? label;
  final TextEditingController? controller;
  final String? hintText;

  /// Shown under the field in the error colour, with a danger border.
  final String? errorText;
  final bool multiline;
  final int? maxLength;
  final bool autofocus;
  final bool enabled;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// The key of the [TextField] itself, for a test or a caller that finds it.
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      hintText: hintText,
      errorText: errorText,
      counterText: '',
      contentPadding: multiline
          ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
          : null,
    );
    final field = TextField(
      key: fieldKey,
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      obscureText: obscureText,
      maxLength: maxLength,
      decoration: decoration,
      style: FlucordTextRole.body.style.copyWith(color: context.surfaces.text),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      expands: multiline,
      maxLines: multiline ? null : 1,
      textAlignVertical: multiline ? TextAlignVertical.top : null,
      keyboardType: multiline ? TextInputType.multiline : null,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label case final label?) FlucordFieldLabel(label),
        if (multiline)
          // The error caption sits under the box, outside its height.
          SizedBox(
            height: _multilineHeight + (errorText == null ? 0 : 20),
            child: field,
          )
        else
          field,
      ],
    );
  }
}

/// A labelled select: a field with a chevron that opens a list of [items],
/// each a value and the text shown for it. A null [onChanged] disables it.
class FlucordSelect<T> extends StatelessWidget {
  const FlucordSelect({
    required this.items,
    required this.value,
    required this.onChanged,
    this.label,
    this.hintText,
    super.key,
  });

  final List<(T, String)> items;

  /// Null shows [hintText]. A value that is not among [items] counts as null.
  final T? value;
  final ValueChanged<T>? onChanged;
  final String? label;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final onChanged = this.onChanged;
    final shown = items.any((item) => item.$1 == value) ? value : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label case final label?) FlucordFieldLabel(label),
        DropdownButtonFormField<T>(
          // The field keeps its own value; a new one from outside replaces
          // it only through a new key.
          key: ValueKey(shown),
          initialValue: shown,
          isExpanded: true,
          icon: const FlucordIcon(FlucordIcons.chevronDown, size: 16),
          iconEnabledColor: surfaces.muted,
          borderRadius: FlucordRadius.medium,
          dropdownColor: surfaces.raised,
          style: FlucordTextRole.label.style.copyWith(color: surfaces.text),
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.fromLTRB(12, 9, 8, 9),
          ),
          hint: hintText == null
              ? null
              : Text(
                  hintText!,
                  style: FlucordTextRole.label.style.copyWith(
                    color: surfaces.captionText,
                  ),
                ),
          items: [
            for (final (itemValue, text) in items)
              DropdownMenuItem(
                value: itemValue,
                child: Text(text, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged == null
              ? null
              : (next) {
                  if (next is T) onChanged(next);
                },
        ),
      ],
    );
  }
}

/// A 32 by 18 on/off pill. Without [onChanged] it shows [value] and cannot
/// be changed.
class FlucordToggle extends StatelessWidget {
  const FlucordToggle({required this.value, this.onChanged, super.key});

  static const Size _size = Size(32, 18);
  static const double _knobOn = 14;
  static const double _knobOff = 12;

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final onChanged = this.onChanged;
    final enabled = onChanged != null;
    void flip() => onChanged?.call(!value);
    final knob = value ? _knobOn : _knobOff;
    final inset = (_size.height - knob) / 2;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              flip();
              return null;
            },
          ),
        },
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasPrimaryFocus;
            return GestureDetector(
              onTap: enabled ? flip : null,
              child: Opacity(
                opacity: enabled ? 1 : 0.5,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: _size.width,
                  height: _size.height,
                  decoration: BoxDecoration(
                    color: value
                        ? surfaces.brand
                        : surfaces.text.withValues(alpha: 0.12),
                    borderRadius: FlucordRadius.full,
                    border: focused
                        ? Border.all(
                            color: surfaces.focusRing,
                            width: 2,
                            strokeAlign: BorderSide.strokeAlignOutside,
                          )
                        : null,
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 120),
                    alignment: value
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: EdgeInsets.all(inset),
                      child: Container(
                        width: knob,
                        height: knob,
                        decoration: BoxDecoration(
                          color: value ? Colors.white : surfaces.muted,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One option of a [FlucordSegmented] group.
final class FlucordSegment<T> {
  const FlucordSegment(this.value, this.label, {this.enabled = true});

  final T value;
  final String label;

  /// A disabled option stays visible: hiding it would misrepresent what can
  /// be chosen elsewhere.
  final bool enabled;
}

/// A tab or segmented option: 28 high, quiet fill and full text when
/// [selected], muted otherwise.
class FlucordTab extends StatelessWidget {
  const FlucordTab({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;

  /// Null disables the tab.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: FlucordRadius.control,
          child: Ink(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? surfaces.quietFill : null,
              borderRadius: FlucordRadius.control,
            ),
            child: Center(
              widthFactor: 1,
              child: Opacity(
                opacity: onPressed == null && !selected ? 0.5 : 1,
                child: Text(
                  label,
                  maxLines: 1,
                  style: FlucordTextRole.label.style.copyWith(
                    color: selected ? surfaces.text : surfaces.muted,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A group of [FlucordTab]s in a recessed box. It wraps rather than
/// overflowing, so a narrow settings pane keeps every option.
class FlucordSegmented<T> extends StatelessWidget {
  const FlucordSegmented({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.keyPrefix,
    super.key,
  });

  final List<FlucordSegment<T>> options;
  final T? selected;
  final ValueChanged<T>? onSelected;

  /// Gives each option the key `'$keyPrefix-$value'`, with an enum value by
  /// its name.
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final onSelected = this.onSelected;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: surfaces.inset,
        borderRadius: FlucordRadius.control,
        border: Border.all(color: surfaces.border),
      ),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          for (final option in options)
            FlucordTab(
              key: keyPrefix == null
                  ? null
                  : ValueKey('$keyPrefix-${_keyName(option.value)}'),
              label: option.label,
              selected: option.value == selected,
              onPressed: option.enabled && onSelected != null
                  ? () => onSelected(option.value)
                  : null,
            ),
        ],
      ),
    );
  }

  static String _keyName(Object? value) =>
      value is Enum ? value.name : '$value';
}
