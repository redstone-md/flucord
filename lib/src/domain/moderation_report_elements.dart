part of 'moderation_report.dart';

/// Element types the report form graph ships.
///
/// [unknown] is not a defensive nicety: the server adds element types without
/// asking the client, and the renderer's own switch has a default branch that
/// renders nothing. A client that threw here would break every report flow the
/// day Discord shipped a new element.
enum ReportElementType {
  freeText('free_text'),
  dropdown('dropdown'),
  countrySelect('country_select'),
  radioGroup('radio_group'),
  checkbox('checkbox'),
  contentUrlInput('content_url_input'),
  text('text'),
  textLineResource('text_line_resource'),
  externalLink('external_link'),
  inlineNotice('inline_notice'),
  success('success'),
  breadcrumbs('breadcrumbs'),
  skip('skip'),
  blockUsers('block_users'),
  ignoreUsers('ignore_users'),
  unknown('');

  const ReportElementType(this.wireName);

  final String wireName;

  static ReportElementType fromWire(Object? value) {
    for (final candidate in values) {
      if (candidate != unknown && candidate.wireName == value) return candidate;
    }
    return unknown;
  }

  /// Whether the element contributes a single string to the submit bag.
  /// Free text, dropdown, country select and radio group all share one flat
  /// string map on the wire.
  bool get isTextInput =>
      this == freeText ||
      this == dropdown ||
      this == countrySelect ||
      this == radioGroup;
}

/// One option of a dropdown, country select or radio group.
final class ReportOption {
  const ReportOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// One row of a checkbox element: the key that goes on the wire and its label.
final class ReportCheckboxOption {
  const ReportCheckboxOption({
    required this.key,
    required this.label,
    this.subtitle,
    this.defaultSelected = false,
  });

  final String key;
  final String label;
  final String? subtitle;
  final bool defaultSelected;
}

/// One element of a node.
final class ReportElement {
  const ReportElement({
    required this.type,
    this.name,
    this.required = false,
    this.title,
    this.subtitle,
    this.description,
    this.placeholder,
    this.body,
    this.rows,
    this.characterLimit,
    this.pattern,
    this.options = const [],
    this.checkboxes = const [],
  });

  final ReportElementType type;

  /// The key this element writes into the submit bag. Display-only elements
  /// have none.
  final String? name;

  /// `should_submit_data`: the Next/Submit button stays disabled until this
  /// element is satisfied.
  final bool required;

  final String? title;
  final String? subtitle;
  final String? description;
  final String? placeholder;
  final String? body;

  /// `1` means a single-line field; anything larger is a text area.
  final int? rows;

  final int? characterLimit;

  /// A regular expression the value must match, as the server sent it.
  final String? pattern;

  final List<ReportOption> options;
  final List<ReportCheckboxOption> checkboxes;

  bool get isSingleLine => rows == null || rows == 1;

  /// Whether [value] satisfies this element.
  ///
  /// Only the four rules the renderer enforces are replicated — requiredness,
  /// the `pattern` regex, non-empty selection, and at least one checkbox key.
  /// Everything else is the server's judgement, returned as `50035`, and
  /// guessing at it locally is how a client blocks a report Discord would have
  /// accepted.
  bool accepts(String? value) {
    if (!required) return true;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return false;
    final source = pattern;
    if (source == null || source.isEmpty) return true;
    // A malformed pattern is the server's problem, not a reason to refuse a
    // report the user has already written.
    final expression = _tryCompile(source);
    return expression == null || expression.hasMatch(text);
  }

  static RegExp? _tryCompile(String source) {
    try {
      return RegExp(source);
    } on FormatException {
      return null;
    }
  }
}
