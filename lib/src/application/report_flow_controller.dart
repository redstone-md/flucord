import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/moderation_report.dart';
import '../domain/moderation_repository.dart';

/// Where a report has got to.
enum ReportFlowStage {
  /// Fetching the form graph. No modal content exists yet.
  loadingMenu,

  /// The menu could not be fetched, so there is no form to show.
  menuUnavailable,

  /// Walking the graph.
  walking,

  /// A submit is in flight.
  submitting,

  /// The server accepted it.
  submitted,
}

/// Drives one report from menu fetch to submission.
///
/// The form is entirely server-authored, so this holds no questions and no
/// answers of its own — it owns the fetch, the in-flight flags, and the one
/// rule the graph cannot express: a node that submits itself must do so exactly
/// once, however many times the widget tree rebuilds around it.
final class ReportFlowController extends ChangeNotifier {
  ReportFlowController(this._repository, {required this.target, this.variant});

  final ModerationRepository _repository;
  final ReportTarget target;

  /// A menu variant, when the caller wants one other than the default.
  final String? variant;

  ReportFlowStage _stage = ReportFlowStage.loadingMenu;
  ReportFlow? _flow;
  Object? _error;
  String? _reportId;
  bool _blocked = false;
  bool _autoSubmitInFlight = false;
  bool _disposed = false;

  ReportFlowStage get stage => _stage;
  ReportFlow? get flow => _flow;
  ReportNode? get node => _flow?.currentNode;

  /// Why the menu could not be loaded, or why the last submit failed.
  Object? get error => _error;

  /// The server-minted report id, once there is one.
  String? get reportId => _reportId;

  /// Whether the reported user has been blocked from this modal.
  bool get isBlocked => _blocked;

  bool get canGoBack =>
      _stage == ReportFlowStage.walking && (_flow?.canGoBack ?? false);

  bool get canAdvance =>
      _stage == ReportFlowStage.walking && (_flow?.canAdvance ?? false);

  /// Fetches the menu. Discord awaits this before opening its modal; the modal
  /// here opens first and shows the wait, which is the same contract with a
  /// visible spinner instead of a frozen menu item.
  Future<void> start() async {
    _stage = ReportFlowStage.loadingMenu;
    _error = null;
    _notify();
    try {
      final menu = await _repository.loadReportMenu(
        target.type,
        variant: variant,
      );
      _flow = ReportFlow(menu: menu, target: target);
      _stage = ReportFlowStage.walking;
    } on Object catch (error) {
      _error = error;
      _stage = ReportFlowStage.menuUnavailable;
    } finally {
      _notify();
    }
  }

  void setValue(String name, String value) {
    _flow?.setValue(name, value);
    _notify();
  }

  void setChecked(String key, {required bool checked}) {
    _flow?.setChecked(key, checked: checked);
    _notify();
  }

  void choose(ReportChoice choice) {
    final flow = _flow;
    if (flow == null || _stage != ReportFlowStage.walking) return;
    // A destination the menu never shipped is a server bug. The renderer counts
    // it and stays put rather than blanking the modal, and so does this.
    if (!flow.choose(choice)) return;
    _error = null;
    _notify();
  }

  void advance() {
    if (_flow?.advance() ?? false) {
      _error = null;
      _notify();
    }
  }

  void goBack() {
    if (_flow?.goBack() ?? false) {
      _error = null;
      _notify();
    }
  }

  /// Runs a node's `is_auto_submit`, at most once per arrival at that node.
  ///
  /// Guarded twice — by the flow's own flag and by an in-flight bool — because
  /// this is called from a build-triggered effect, and a second submit would
  /// file a second report against the same person.
  Future<void> submitIfAutomatic() async {
    final flow = _flow;
    if (flow == null || _autoSubmitInFlight) return;
    if (_stage != ReportFlowStage.walking || !flow.needsAutoSubmit) return;
    _autoSubmitInFlight = true;
    try {
      await _send(flow.buildAutoSubmission());
    } finally {
      _autoSubmitInFlight = false;
    }
  }

  /// Sends the report the user has filled in.
  Future<void> submit() async {
    final flow = _flow;
    if (flow == null || _stage != ReportFlowStage.walking) return;
    if (!flow.canAdvance) return;
    await _send(flow.buildSubmission());
  }

  /// Blocks the reported user, when the report is about one.
  ///
  /// Offered from the report modal because Discord offers it there, and because
  /// the moment somebody finishes reporting a stranger is exactly when they
  /// want them gone.
  Future<bool> blockReportedUser() async {
    final subject = target;
    if (subject is! UserReportTarget || _blocked) return false;
    try {
      await _repository.blockUser(subject.userId);
      _blocked = true;
      _notify();
      return true;
    } on Object catch (error) {
      _error = error;
      _notify();
      return false;
    }
  }

  Future<void> _send(ReportSubmission submission) async {
    final flow = _flow;
    if (flow == null) return;
    _stage = ReportFlowStage.submitting;
    _error = null;
    _notify();
    try {
      _reportId = await _repository.submitReport(submission);
      flow.completeWith(succeeded: true);
      _stage = ReportFlowStage.submitted;
    } on Object catch (error) {
      _error = error;
      // Stay on the node the user submitted from rather than jumping to the
      // failure screen: the renderer shows the error inline so a retry does not
      // cost them everything they typed.
      _stage = ReportFlowStage.walking;
    } finally {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
