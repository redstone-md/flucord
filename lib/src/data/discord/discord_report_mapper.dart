import '../../domain/moderation_report.dart';

/// Reads `GET /reporting/menu/{type}` into the form graph.
///
/// The menu is entirely server-authored, so every field is optional and every
/// unrecognised value degrades instead of throwing. Discord ships element and
/// button types this build has never heard of, and its own renderer's switch
/// has a default branch that draws nothing — a parser that refused the whole
/// menu over one of them would take away the report flow entirely.
abstract final class DiscordReportMapper {
  /// The most nodes one menu may carry.
  ///
  /// The graph drives a widget per node, so its size is a wire-supplied number
  /// that decides how much this client allocates. Real menus hold a few dozen;
  /// the bound exists so a malformed or hostile response cannot turn one report
  /// into an out-of-memory crash.
  static const maxNodes = 512;

  /// The most branches, elements or options one node may carry.
  static const maxNodeItems = 128;

  static ReportMenu? menu(Map<String, Object?> payload) {
    final rootNodeId = _string(payload['root_node_id']);
    final successNodeId = _string(payload['success_node_id']);
    final failNodeId = _string(payload['fail_node_id']);
    final rawNodes = payload['nodes'];
    if (rootNodeId == null ||
        successNodeId == null ||
        failNodeId == null ||
        rawNodes is! Map) {
      return null;
    }
    final nodes = <String, ReportNode>{};
    for (final entry in rawNodes.entries) {
      if (nodes.length >= maxNodes) break;
      final id = entry.key.toString();
      final value = entry.value;
      if (value is! Map) continue;
      nodes[id] = node(id, value.cast<String, Object?>());
    }
    if (!nodes.containsKey(rootNodeId)) return null;
    return ReportMenu(
      nodes: Map.unmodifiable(nodes),
      rootNodeId: rootNodeId,
      successNodeId: successNodeId,
      failNodeId: failNodeId,
      version: payload['version'],
      variant: _string(payload['variant']),
      language: _string(payload['language']),
    );
  }

  static ReportNode node(String id, Map<String, Object?> payload) {
    final rawButton = payload['button'];
    return ReportNode(
      id: _string(payload['id']) ?? id,
      key: _string(payload['key']),
      header: _string(payload['header']),
      subheader: _string(payload['subheader']),
      info: _string(payload['info']),
      reportSubtype: _string(payload['report_type']),
      isAutoSubmit: payload['is_auto_submit'] == true,
      button: rawButton is Map
          ? ReportButton(
              type: ReportButtonType.fromWire(rawButton['type']),
              target: _string(rawButton['target']),
            )
          : null,
      choices: _choices(payload['children']),
      elements: _elements(payload['elements']),
    );
  }

  /// `children` is an array of `[label, nodeId]` pairs.
  static List<ReportChoice> _choices(Object? value) {
    final choices = <ReportChoice>[];
    for (final raw in _list(value)) {
      if (choices.length >= maxNodeItems) break;
      if (raw is! List || raw.length < 2) continue;
      final nodeId = _string(raw[1]);
      if (nodeId == null) continue;
      choices.add(
        ReportChoice(label: _string(raw[0]) ?? nodeId, nodeId: nodeId),
      );
    }
    return List.unmodifiable(choices);
  }

  static List<ReportElement> _elements(Object? value) {
    final elements = <ReportElement>[];
    for (final raw in _list(value)) {
      if (elements.length >= maxNodeItems) break;
      if (raw is! Map) continue;
      elements.add(element(raw.cast<String, Object?>()));
    }
    return List.unmodifiable(elements);
  }

  static ReportElement element(Map<String, Object?> payload) {
    final type = ReportElementType.fromWire(payload['type']);
    final rawData = payload['data'];
    final data = rawData is Map
        ? rawData.cast<String, Object?>()
        : const <String, Object?>{};
    return ReportElement(
      type: type,
      name: _string(payload['name']),
      required: payload['should_submit_data'] == true,
      title: _string(data['title']),
      subtitle: _string(data['subtitle']),
      description: _string(data['description']),
      placeholder: _string(data['placeholder']),
      body: _string(data['body']) ?? _string(data['header']),
      rows: _int(data['rows']),
      characterLimit: _int(data['character_limit']),
      pattern: _string(data['pattern']),
      options: _options(data['options']),
      // A checkbox element's `data` is the tuple array itself, not an object
      // wrapping one, which is why it is read off the raw value.
      checkboxes: _checkboxes(rawData),
    );
  }

  static List<ReportOption> _options(Object? value) {
    final options = <ReportOption>[];
    for (final raw in _list(value)) {
      if (options.length >= maxNodeItems) break;
      if (raw is! Map) continue;
      final optionValue = _string(raw['value']);
      if (optionValue == null) continue;
      options.add(
        ReportOption(
          value: optionValue,
          label: _string(raw['label']) ?? optionValue,
        ),
      );
    }
    return List.unmodifiable(options);
  }

  /// `[key, label, subtitle, defaultSelected]`, positionally.
  static List<ReportCheckboxOption> _checkboxes(Object? value) {
    final rows = <ReportCheckboxOption>[];
    for (final raw in _list(value)) {
      if (rows.length >= maxNodeItems) break;
      if (raw is! List || raw.isEmpty) continue;
      final key = _string(raw[0]);
      if (key == null) continue;
      rows.add(
        ReportCheckboxOption(
          key: key,
          label: raw.length > 1 ? _string(raw[1]) ?? key : key,
          subtitle: raw.length > 2 ? _string(raw[2]) : null,
          defaultSelected: raw.length > 3 && raw[3] == true,
        ),
      );
    }
    return List.unmodifiable(rows);
  }

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static String? _string(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }

  static int? _int(Object? value) => switch (value) {
    final int raw => raw,
    final String raw => int.tryParse(raw),
    _ => null,
  };
}
