import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/report_flow_controller.dart';
import 'package:flucord/src/domain/moderation_report.dart';
import 'package:flucord/src/domain/moderation_repository.dart';
import 'package:flucord/src/presentation/widgets/report_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('walks the server graph and submits', (tester) async {
    final repository = _FakeModerationRepository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.pumpAndSettle();

    expect(find.text('What is wrong?'), findsOneWidget);
    // No submit button on the root: the graph offers branches instead.
    expect(find.byKey(const ValueKey('report-primary-action')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('report-choice-spam')));
    await tester.pumpAndSettle();
    expect(find.text('Tell us what happened'), findsOneWidget);

    // The submit button stays inert until the required field is filled.
    expect(_primaryEnabled(tester), isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('report-input-details')),
      'they kept messaging me',
    );
    await tester.pumpAndSettle();
    expect(_primaryEnabled(tester), isTrue);

    await tester.tap(find.byKey(const ValueKey('report-checkbox-scam')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-radio-severity-high')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('report-primary-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('report-submitted')), findsOneWidget);
    final body = repository.submitted!.body;
    expect(body['name'], 'user');
    expect(body['breadcrumbs'], ['root', 'spam']);
    final elements = body['elements']! as Map<String, Object?>;
    expect(elements['details'], 'they kept messaging me');
    expect(elements['reasons'], ['scam']);
    expect(elements['severity'], 'high');
    expect(controller.reportId, '987654321098765432');
  });

  testWidgets('blocks the reported user from the success screen', (
    tester,
  ) async {
    final repository = _FakeModerationRepository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-choice-spam')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('report-input-details')),
      'spam',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-primary-action')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('report-block-user')));
    await tester.pumpAndSettle();
    expect(repository.blocked, ['123456789012345678']);
    expect(find.text('Blocked'), findsOneWidget);
  });

  testWidgets('a refused block leaves the button offering to try again', (
    tester,
  ) async {
    final repository = _FakeModerationRepository()..failBlock = true;
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-choice-spam')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('report-input-details')),
      'spam',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-primary-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-block-user')));
    await tester.pumpAndSettle();
    expect(controller.isBlocked, isFalse);
    expect(controller.error, isNotNull);
    expect(find.text('Also block them'), findsOneWidget);
  });

  testWidgets('goes back and keeps what was typed', (tester) async {
    final controller = _controller(_FakeModerationRepository());
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-choice-spam')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('report-input-details')),
      'typed',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-back')));
    await tester.pumpAndSettle();
    expect(find.text('What is wrong?'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-back')), findsNothing);
  });

  testWidgets('a next button walks to the node it names', (tester) async {
    final controller = _controller(_FakeModerationRepository());
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-choice-other')));
    await tester.pumpAndSettle();
    expect(find.text('Next'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report-primary-action')));
    await tester.pumpAndSettle();
    expect(find.text('Tell us what happened'), findsOneWidget);
  });

  testWidgets('an unreadable menu offers a retry, not an empty form', (
    tester,
  ) async {
    final repository = _FakeModerationRepository()..failMenu = true;
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-unavailable')), findsOneWidget);
    repository.failMenu = false;
    await tester.tap(find.byKey(const ValueKey('report-retry')));
    await tester.pumpAndSettle();
    expect(find.text('What is wrong?'), findsOneWidget);
  });

  testWidgets('a failed submit stays on the node it came from', (tester) async {
    final repository = _FakeModerationRepository()..failSubmit = true;
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-choice-spam')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('report-input-details')),
      'spam',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-primary-action')));
    await tester.pumpAndSettle();
    // The notice sits under the form, so the list has to be scrolled to it.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-submit-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-primary-action')), findsOneWidget);
  });

  testWidgets('an auto-submit node files the report once', (tester) async {
    final repository = _FakeModerationRepository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-choice-auto')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-submitted')), findsOneWidget);
    expect(repository.submitCount, 1);
  });

  testWidgets('an unknown element type renders nothing at all', (tester) async {
    final controller = _controller(_FakeModerationRepository());
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-choice-strange')));
    await tester.pumpAndSettle();
    expect(find.text('A future element'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a compact window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(_FakeModerationRepository());
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('report-choice-spam')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('report-dialog')), findsOneWidget);
  });
}

bool _primaryEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('report-primary-action')),
        )
        .onPressed !=
    null;

ReportFlowController _controller(ModerationRepository repository) =>
    ReportFlowController(
      repository,
      target: const UserReportTarget(
        userId: '123456789012345678',
        guildId: '111111111111111111',
      ),
    );

Future<void> _pump(WidgetTester tester, ReportFlowController controller) =>
    tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: ReportDialog(controller: controller),
      ),
    );

final class _FakeModerationRepository implements ModerationRepository {
  bool failMenu = false;
  bool failSubmit = false;
  bool failBlock = false;
  int submitCount = 0;
  ReportSubmission? submitted;
  final List<String> blocked = [];

  @override
  Future<ReportMenu> loadReportMenu(ReportType type, {String? variant}) async {
    if (failMenu) throw StateError('offline');
    return _menu;
  }

  @override
  Future<String?> submitReport(ReportSubmission submission) async {
    submitCount++;
    if (failSubmit) throw StateError('rejected');
    submitted = submission;
    return '987654321098765432';
  }

  @override
  Future<void> blockUser(String userId) async {
    if (failBlock) throw StateError('refused');
    blocked.add(userId);
  }

  @override
  Future<void> unblockUser(String userId) async => blocked.remove(userId);

  @override
  Future<void> ignoreUser(String userId) async {}

  @override
  Future<void> unignoreUser(String userId) async {}
}

const _menu = ReportMenu(
  rootNodeId: 'root',
  successNodeId: 'ok',
  failNodeId: 'bad',
  version: 7,
  language: 'en-GB',
  nodes: {
    'root': ReportNode(
      id: 'root',
      header: 'What is wrong?',
      info: 'Reports stay confidential',
      choices: [
        ReportChoice(label: 'Spam', nodeId: 'spam'),
        ReportChoice(label: 'Something else', nodeId: 'other'),
        ReportChoice(label: 'Report immediately', nodeId: 'auto'),
        ReportChoice(label: 'Strange', nodeId: 'strange'),
      ],
    ),
    'spam': ReportNode(
      id: 'spam',
      header: 'Tell us what happened',
      button: ReportButton(type: ReportButtonType.submit),
      elements: [
        ReportElement(
          type: ReportElementType.text,
          body: 'Anything you add helps.',
        ),
        ReportElement(
          type: ReportElementType.freeText,
          name: 'details',
          title: 'Details',
          required: true,
          rows: 3,
          characterLimit: 400,
        ),
        ReportElement(
          type: ReportElementType.checkbox,
          name: 'reasons',
          title: 'What kind?',
          checkboxes: [
            ReportCheckboxOption(
              key: 'scam',
              label: 'Scam links',
              subtitle: 'Phishing or crypto',
            ),
          ],
        ),
        ReportElement(
          type: ReportElementType.radioGroup,
          name: 'severity',
          title: 'How bad?',
          options: [
            ReportOption(value: 'low', label: 'Annoying'),
            ReportOption(value: 'high', label: 'Dangerous'),
          ],
        ),
        ReportElement(
          type: ReportElementType.dropdown,
          name: 'where',
          title: 'Where?',
          options: [ReportOption(value: 'dm', label: 'In a DM')],
        ),
      ],
    ),
    'other': ReportNode(
      id: 'other',
      header: 'Something else',
      button: ReportButton(type: ReportButtonType.next, target: 'spam'),
    ),
    'auto': ReportNode(id: 'auto', header: 'Filing', isAutoSubmit: true),
    'strange': ReportNode(
      id: 'strange',
      header: 'Strange',
      elements: [
        ReportElement(
          type: ReportElementType.unknown,
          title: 'A future element',
        ),
        ReportElement(type: ReportElementType.freeText),
        ReportElement(type: ReportElementType.dropdown, name: 'empty'),
      ],
    ),
    'ok': ReportNode(id: 'ok', header: 'Thanks'),
    'bad': ReportNode(id: 'bad', header: 'That failed'),
  },
);
