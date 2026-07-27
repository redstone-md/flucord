import 'package:flutter/material.dart';

import '../../application/report_flow_controller.dart';
import '../../domain/moderation_report.dart';
import '../../theme/flucord_theme.dart';

/// Renders one server-supplied report element.
///
/// The `default` branch draws nothing on purpose. Discord ships element types
/// newer than any given client — entity previews and one-tap actions among them
/// — and its own renderer skips the ones it does not know rather than failing
/// the node. A client that threw here would lose the whole report flow the day
/// a new element shipped.
class ReportElementView extends StatelessWidget {
  const ReportElementView({
    required this.controller,
    required this.element,
    super.key,
  });

  final ReportFlowController controller;
  final ReportElement element;

  @override
  Widget build(BuildContext context) => switch (element.type) {
    ReportElementType.freeText => _freeText(context),
    ReportElementType.contentUrlInput => _freeText(context),
    ReportElementType.dropdown ||
    ReportElementType.countrySelect => _dropdown(context),
    ReportElementType.radioGroup => _radioGroup(context),
    ReportElementType.checkbox => _checkboxes(context),
    ReportElementType.text ||
    ReportElementType.inlineNotice => _paragraph(context),
    _ => const SizedBox.shrink(),
  };

  Widget _freeText(BuildContext context) {
    final name = element.name;
    if (name == null) return const SizedBox.shrink();
    return _wrap(
      context,
      TextField(
        key: ValueKey('report-input-$name'),
        maxLines: element.isSingleLine ? 1 : 4,
        maxLength: element.characterLimit,
        decoration: InputDecoration(
          isDense: true,
          hintText: element.placeholder,
          counterText: '',
        ),
        onChanged: (value) => controller.setValue(name, value),
      ),
    );
  }

  Widget _dropdown(BuildContext context) {
    final name = element.name;
    if (name == null || element.options.isEmpty) {
      return const SizedBox.shrink();
    }
    final current = controller.flow?.valueOf(name);
    return _wrap(
      context,
      DropdownButtonFormField<String>(
        key: ValueKey('report-select-$name'),
        initialValue: element.options.any((option) => option.value == current)
            ? current
            : null,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          hintText: element.placeholder,
        ),
        items: [
          for (final option in element.options)
            DropdownMenuItem(
              value: option.value,
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) {
          if (value != null) controller.setValue(name, value);
        },
      ),
    );
  }

  Widget _radioGroup(BuildContext context) {
    final name = element.name;
    if (name == null) return const SizedBox.shrink();
    final current = controller.flow?.valueOf(name);
    return _wrap(
      context,
      RadioGroup<String>(
        groupValue: current,
        onChanged: (value) {
          if (value != null) controller.setValue(name, value);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in element.options)
              RadioListTile<String>(
                key: ValueKey('report-radio-$name-${option.value}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(option.label),
                value: option.value,
              ),
          ],
        ),
      ),
    );
  }

  Widget _checkboxes(BuildContext context) => _wrap(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in element.checkboxes)
          CheckboxListTile(
            key: ValueKey('report-checkbox-${option.key}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(option.label),
            subtitle: option.subtitle == null ? null : Text(option.subtitle!),
            value: controller.flow?.isChecked(option.key) ?? false,
            onChanged: (checked) =>
                controller.setChecked(option.key, checked: checked ?? false),
          ),
      ],
    ),
  );

  Widget _paragraph(BuildContext context) {
    final body = element.body ?? element.title;
    if (body == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        body,
        style: TextStyle(fontSize: 12, color: context.surfaces.muted),
      ),
    );
  }

  Widget _wrap(BuildContext context, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (element.title != null) ...[
          Text(
            element.title!,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
        ],
        child,
      ],
    ),
  );
}
