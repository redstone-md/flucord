part of 'moderation_report.dart';

/// One step the user took, captured as they left the node.
final class ReportHistoryEntry {
  const ReportHistoryEntry({
    required this.nodeRef,
    required this.destinationLabel,
    required this.destinationNodeId,
    this.textInput = const {},
    this.multiSelect = const {},
  });

  /// The node this step was taken *from*. The breadcrumb trail is the list of
  /// these, in order.
  final String nodeRef;

  final String destinationLabel;
  final String destinationNodeId;

  /// What the user typed or picked on [nodeRef], keyed by element name.
  final Map<String, String> textInput;

  /// The checkbox keys selected on [nodeRef].
  final Set<String> multiSelect;
}

/// A finished report, ready for `POST /reporting/{type}`.
final class ReportSubmission {
  const ReportSubmission({required this.type, required this.body});

  final ReportType type;
  final Map<String, Object?> body;
}

/// Walks the server-supplied report graph.
///
/// The whole form is server data — every label, branch, option and validation
/// rule — so this holds no knowledge of what a report says, only of how a
/// traversal is recorded. That is deliberate: the submit body is a pure
/// function of `(menu, target, history)`, which is the only part with real
/// branching and therefore the only part worth testing exhaustively.
final class ReportFlow {
  ReportFlow({required this.menu, required this.target})
    : _currentNodeId = menu.rootNodeId {
    _enter(menu.rootNodeId, record: false);
  }

  final ReportMenu menu;
  final ReportTarget target;

  final List<ReportHistoryEntry> _history = [];
  final Map<String, String> _textInput = {};
  final Set<String> _multiSelect = {};

  String _currentNodeId;
  bool _autoSubmitted = false;

  String get currentNodeId => _currentNodeId;

  /// The node in view, or `null` when the menu does not contain it. A menu
  /// that names a node it did not ship is a server bug the renderer counts and
  /// bails on rather than crashing.
  ReportNode? get currentNode => menu[_currentNodeId];

  List<ReportHistoryEntry> get history => List.unmodifiable(_history);

  /// The node ids visited, in order — the `breadcrumbs` array.
  List<String> get breadcrumbs => [for (final entry in _history) entry.nodeRef];

  Map<String, String> get textInput => Map.unmodifiable(_textInput);
  Set<String> get multiSelect => Set.unmodifiable(_multiSelect);

  bool get isOnSuccessNode => _currentNodeId == menu.successNodeId;
  bool get isOnFailureNode => _currentNodeId == menu.failNodeId;
  bool get canGoBack => _history.isNotEmpty;

  /// Whether the node arrived already submitted, and has not been yet.
  bool get needsAutoSubmit =>
      (currentNode?.isAutoSubmit ?? false) && !_autoSubmitted;

  String? valueOf(String name) => _textInput[name];

  bool isChecked(String key) => _multiSelect.contains(key);

  void setValue(String name, String value) => _textInput[name] = value;

  void setChecked(String key, {required bool checked}) {
    if (checked) {
      _multiSelect.add(key);
    } else {
      _multiSelect.remove(key);
    }
  }

  /// Whether every required element on the current node is satisfied.
  bool get canAdvance {
    final node = currentNode;
    if (node == null) return false;
    for (final element in node.elements) {
      if (!element.required) continue;
      final satisfied = switch (element.type) {
        ReportElementType.checkbox => _multiSelect.isNotEmpty,
        ReportElementType.contentUrlInput => _acceptsContentUrl(element),
        _ =>
          !element.type.isTextInput ||
              element.accepts(_textInput[element.name ?? '']),
      };
      if (!satisfied) return false;
    }
    return true;
  }

  /// Follows [choice]. Answers false when the destination is not in the menu.
  bool choose(ReportChoice choice) =>
      _navigate(label: choice.label, nodeId: choice.nodeId);

  /// Presses the current node's `next` button.
  bool advance() {
    final button = currentNode?.button;
    final destination = button?.target;
    if (button?.type != ReportButtonType.next || destination == null) {
      return false;
    }
    return _navigate(label: '', nodeId: destination);
  }

  /// Returns to the previous node, restoring what was typed there.
  bool goBack() {
    if (_history.isEmpty) return false;
    final entry = _history.removeLast();
    _textInput
      ..clear()
      ..addAll(entry.textInput);
    _multiSelect
      ..clear()
      ..addAll(entry.multiSelect);
    _currentNodeId = entry.nodeRef;
    return true;
  }

  /// The body for a submit pressed on the current node.
  ///
  /// Appending the synthetic step first is what puts the submitting node into
  /// `breadcrumbs`; without it the server sees a trail that stops one node
  /// short of the answer the user actually gave.
  ReportSubmission buildSubmission() {
    _history.add(
      ReportHistoryEntry(
        nodeRef: _currentNodeId,
        destinationLabel: '',
        destinationNodeId: menu.successNodeId,
        textInput: Map.of(_textInput),
        multiSelect: Set.of(_multiSelect),
      ),
    );
    return _submissionFromHistory();
  }

  /// The body for a node that submits itself on arrival.
  ReportSubmission buildAutoSubmission() {
    _autoSubmitted = true;
    _history.add(
      ReportHistoryEntry(
        nodeRef: _currentNodeId,
        destinationLabel: '',
        destinationNodeId: _currentNodeId,
        textInput: Map.of(_textInput),
        multiSelect: Set.of(_multiSelect),
      ),
    );
    return _submissionFromHistory();
  }

  /// Moves to the terminal node a finished submit lands on.
  void completeWith({required bool succeeded}) {
    _currentNodeId = succeeded ? menu.successNodeId : menu.failNodeId;
  }

  ReportSubmission _submissionFromHistory() => ReportSubmission(
    type: target.type,
    body: {
      'version': menu.version,
      'variant': menu.variant,
      // The renderer defaults a null menu language to English rather than
      // omitting the key, and the server echoes it back on the report.
      'language': menu.language ?? 'en',
      'breadcrumbs': breadcrumbs,
      'elements': _elements(),
      'name': target.type.wireName,
      ...target.toEntityKeys(),
    },
  );

  Map<String, Object?> _elements() {
    final bag = <String, Object?>{};
    for (final entry in _history) {
      final node = menu[entry.nodeRef];
      if (node == null) continue;
      final checkbox = node.multiSelect;
      final checkboxName = checkbox?.name;
      if (checkboxName != null) {
        bag[checkboxName] = entry.multiSelect.toList(growable: false);
      }
      for (final element in node.elements) {
        final name = element.name;
        if (name == null) continue;
        final value = entry.textInput[name];
        if (value == null) continue;
        if (element.type.isTextInput) {
          bag[name] = value;
          continue;
        }
        if (element.type == ReportElementType.contentUrlInput) {
          bag[name] = value;
          final link = entry.textInput['${name}_message_link'];
          if (link != null) bag['${name}_message_link'] = link;
        }
      }
    }
    return bag;
  }

  bool _navigate({required String label, required String nodeId}) {
    final resolved = _resolveSkips(nodeId);
    if (menu[resolved] == null) return false;
    _history.add(
      ReportHistoryEntry(
        nodeRef: _currentNodeId,
        destinationLabel: label,
        destinationNodeId: resolved,
        textInput: Map.of(_textInput),
        multiSelect: Set.of(_multiSelect),
      ),
    );
    _enter(resolved, record: true);
    return true;
  }

  /// A node whose only content is a `skip` element forwards straight through
  /// and never enters the history. Without this, flows that use a skip node as
  /// a router deadlock on a screen with nothing to press.
  String _resolveSkips(String nodeId) {
    var current = nodeId;
    final seen = <String>{};
    while (seen.add(current)) {
      final node = menu[current];
      if (node == null || node.skip == null) return current;
      final button = node.button;
      final target = button?.target;
      if (button?.type != ReportButtonType.next || target == null) {
        return current;
      }
      current = target;
    }
    return current;
  }

  void _enter(String nodeId, {required bool record}) {
    _currentNodeId = nodeId;
    _autoSubmitted = false;
    if (!record) return;
    _textInput.clear();
    _multiSelect.clear();
    for (final option in currentNode?.multiSelect?.checkboxes ?? const []) {
      if (option.defaultSelected) _multiSelect.add(option.key);
    }
  }

  bool _acceptsContentUrl(ReportElement element) {
    final name = element.name;
    if (name == null) return true;
    final value = _textInput[name]?.trim() ?? '';
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    // A link to Discord's own CDN identifies nothing on its own — the same
    // attachment URL is reachable from any message — so the server also wants
    // the message it was posted in.
    if (!_discordCdnHosts.contains(uri.host)) return true;
    final link = _textInput['${name}_message_link']?.trim() ?? '';
    return _messageLink.hasMatch(link);
  }

  static const _discordCdnHosts = {
    'cdn.discordapp.com',
    'media.discordapp.net',
  };

  static final _messageLink = RegExp(
    r'^https://(ptb\.|canary\.)?discord(app)?\.com/channels/(@me|\d+)/\d+/\d+$',
  );
}
