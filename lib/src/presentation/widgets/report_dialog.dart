import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/report_flow_controller.dart';
import '../../domain/moderation_report.dart';
import '../../theme/flucord_theme.dart';
import 'report_element_views.dart';

/// Discord's in-app report modal.
///
/// Nothing in here decides what a report can say. The nodes, their branches,
/// their inputs and their validation rules all arrive from
/// `GET /reporting/menu/{type}`, and an element type this build has never seen
/// renders as nothing rather than breaking the flow — which is exactly what the
/// official renderer does, because Discord ships new element types without
/// waiting for clients.
class ReportDialog extends StatefulWidget {
  const ReportDialog({required this.controller, super.key});

  final ReportFlowController controller;

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.start());
    widget.controller.addListener(_maybeAutoSubmit);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_maybeAutoSubmit);
    super.dispose();
  }

  /// A node marked `is_auto_submit` files the report the moment it is reached.
  /// The controller guards against a second send; this only has to notice.
  void _maybeAutoSubmit() {
    if (widget.controller.flow?.needsAutoSubmit ?? false) {
      unawaited(widget.controller.submitIfAutomatic());
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('report-dialog'),
    backgroundColor: context.surfaces.surface,
    insetPadding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => _body(context),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    final controller = widget.controller;
    return switch (controller.stage) {
      ReportFlowStage.loadingMenu => const Padding(
        key: ValueKey('report-loading'),
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      ReportFlowStage.menuUnavailable => _unavailable(context),
      ReportFlowStage.submitted => _submitted(context),
      ReportFlowStage.walking || ReportFlowStage.submitting => _form(context),
    };
  }

  Widget _unavailable(BuildContext context) => Padding(
    key: const ValueKey('report-unavailable'),
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off, size: 28),
        const SizedBox(height: 12),
        const Text('The report form could not be loaded.'),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Close'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('report-retry'),
              onPressed: () => unawaited(widget.controller.start()),
              child: const Text('Retry'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _submitted(BuildContext context) {
    final target = widget.controller.target;
    return Padding(
      key: const ValueKey('report-submitted'),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_outline, size: 32),
          const SizedBox(height: 12),
          const Text(
            'Thanks for the report.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Discord will review it. Nothing you do here is shown to them.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
          ),
          const SizedBox(height: 18),
          if (target is UserReportTarget)
            OutlinedButton.icon(
              key: const ValueKey('report-block-user'),
              onPressed: widget.controller.isBlocked
                  ? null
                  : () => unawaited(widget.controller.blockReportedUser()),
              icon: const Icon(Icons.block, size: 16),
              label: Text(
                widget.controller.isBlocked ? 'Blocked' : 'Also block them',
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('report-done'),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final controller = widget.controller;
    final node = controller.node;
    if (node == null) {
      return const Padding(
        key: ValueKey('report-node-missing'),
        padding: EdgeInsets.all(28),
        child: Text('This report step is unavailable.'),
      );
    }
    final submitting = controller.stage == ReportFlowStage.submitting;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, node),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            children: [
              if (node.info != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    node.info!,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.surfaces.muted,
                    ),
                  ),
                ),
              for (final element in node.elements)
                ReportElementView(
                  key: ValueKey(
                    'report-element-${element.name ?? element.type.name}',
                  ),
                  controller: controller,
                  element: element,
                ),
              for (final choice in node.choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedButton(
                    key: ValueKey('report-choice-${choice.nodeId}'),
                    onPressed: submitting
                        ? null
                        : () => controller.choose(choice),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(choice.label),
                    ),
                  ),
                ),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'That report could not be sent. Try again.',
                    key: const ValueKey('report-submit-error'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _footer(context, node, submitting: submitting),
      ],
    );
  }

  Widget _header(BuildContext context, ReportNode node) => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.surfaces.border)),
    ),
    child: Row(
      children: [
        if (widget.controller.canGoBack)
          IconButton(
            key: const ValueKey('report-back'),
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.controller.goBack,
          ),
        Expanded(
          child: Text(
            node.header ?? 'Report',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          key: const ValueKey('report-close'),
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );

  Widget _footer(
    BuildContext context,
    ReportNode node, {
    required bool submitting,
  }) {
    final button = node.button;
    if (button == null ||
        button.type == ReportButtonType.cancel ||
        button.type == ReportButtonType.unknown) {
      return const SizedBox(height: 12);
    }
    final controller = widget.controller;
    final isSubmit = button.type == ReportButtonType.submit;
    final enabled = !submitting && controller.canAdvance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (submitting)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          FilledButton(
            key: const ValueKey('report-primary-action'),
            onPressed: enabled
                ? (isSubmit
                      ? () => unawaited(controller.submit())
                      : controller.advance)
                : null,
            child: Text(isSubmit ? 'Submit report' : 'Next'),
          ),
        ],
      ),
    );
  }
}

/// Opens the report modal for [target].
Future<void> showReportDialog({
  required BuildContext context,
  required ReportFlowController controller,
}) => showDialog<void>(
  context: context,
  builder: (_) => ReportDialog(controller: controller),
);
