import 'dart:async';

import 'package:flucord/src/application/stage_controller.dart';
import 'package:flucord/src/domain/stage_channel.dart';
import 'package:flucord/src/presentation/widgets/stage_controls.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, StageController controller) =>
      tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => StageControls(controller: controller),
            ),
          ),
        ),
      );

  testWidgets('shows nothing on a transport with no stages', (tester) async {
    final controller = StageController(() => null);
    addTearDown(controller.dispose);

    await pump(tester, controller);

    expect(find.byKey(const ValueKey('stage-controls')), findsNothing);
  });

  testWidgets('shows nothing until a stage channel is on screen', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final controller = StageController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);

    expect(find.byKey(const ValueKey('stage-controls')), findsNothing);
  });

  testWidgets('a channel with no live stage offers no actions', (tester) async {
    final repository = _FakeRepository();
    final controller = StageController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('stage-1');
    await tester.pumpAndSettle();

    expect(find.text('No stage is running here'), findsOne);
    expect(find.byKey(const ValueKey('stage-request')), findsNothing);
  });

  testWidgets('the audience can ask, and take the ask back', (tester) async {
    final repository = _FakeRepository(
      stage: const StageInstance(
        id: 'i',
        channelId: 'stage-1',
        guildId: 'guild-1',
        topic: 'Release notes',
      ),
    );
    final controller = StageController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('stage-1');
    await tester.pumpAndSettle();

    expect(find.text('Release notes'), findsOne);
    expect(find.text('You are in the audience.'), findsOne);

    await tester.tap(find.byKey(const ValueKey('stage-request')));
    await tester.pumpAndSettle();

    expect(repository.requested, ['stage-1']);
    expect(find.text('Your hand is raised.'), findsOne);

    await tester.tap(find.byKey(const ValueKey('stage-cancel-request')));
    await tester.pumpAndSettle();

    expect(repository.cancelled, ['stage-1']);
    expect(find.byKey(const ValueKey('stage-request')), findsOne);
  });

  testWidgets('an invitation is accepted or declined', (tester) async {
    final repository = _FakeRepository(
      stage: const StageInstance(
        id: 'i',
        channelId: 'stage-1',
        guildId: 'guild-1',
      ),
      presence: const StagePresence(channelId: 'stage-1', isInvited: true),
    );
    final controller = StageController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('stage-1');
    await tester.pumpAndSettle();

    // A stage with no topic still says it is live rather than showing nothing.
    expect(find.text('Stage is live'), findsOne);
    expect(find.text('A moderator invited you to speak.'), findsOne);
    expect(find.byKey(const ValueKey('stage-decline')), findsOne);

    await tester.tap(find.byKey(const ValueKey('stage-accept')));
    await tester.pumpAndSettle();

    expect(repository.speaking, [true]);
    expect(find.text('You are on stage.'), findsOne);

    await tester.tap(find.byKey(const ValueKey('stage-step-down')));
    await tester.pumpAndSettle();

    expect(repository.speaking, [true, false]);
    expect(find.text('You are in the audience.'), findsOne);
  });

  testWidgets('an invitation can simply be declined', (tester) async {
    final repository = _FakeRepository(
      stage: const StageInstance(
        id: 'i',
        channelId: 'stage-1',
        guildId: 'guild-1',
      ),
      presence: const StagePresence(channelId: 'stage-1', isInvited: true),
    );
    final controller = StageController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('stage-1');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stage-decline')));
    await tester.pumpAndSettle();

    expect(repository.cancelled, ['stage-1']);
    expect(find.text('You are in the audience.'), findsOne);
  });

  testWidgets('a refused action is shown', (tester) async {
    final repository = _FakeRepository(
      stage: const StageInstance(
        id: 'i',
        channelId: 'stage-1',
        guildId: 'guild-1',
      ),
      failWrites: true,
    );
    final controller = StageController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('stage-1');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stage-request')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('stage-error')), findsOne);
    expect(find.text('You are in the audience.'), findsOne);
  });

  testWidgets('a listener is offered nothing to manage', (tester) async {
    final repository = _FakeRepository(
      stage: const StageInstance(
        id: 'i',
        channelId: 'stage-1',
        guildId: 'guild-1',
      ),
    );
    final controller = StageController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('stage-1');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('stage-moderator-menu')), findsNothing);
    expect(find.byKey(const ValueKey('stage-start')), findsNothing);
  });

  testWidgets('a moderator starts a stage through the topic dialog', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final controller = StageController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('stage-1', canModerate: true);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stage-start')));
    await tester.pumpAndSettle();

    // Discord requires a topic, so an empty one cannot be submitted.
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('stage-topic-confirm')),
    );
    expect(confirm.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('stage-topic-field')),
      '  Release notes  ',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stage-topic-confirm')));
    await tester.pumpAndSettle();

    expect(repository.started, ['Release notes']);
    expect(find.text('Release notes'), findsOne);
  });

  testWidgets('backing out of the dialog starts nothing', (tester) async {
    final repository = _FakeRepository();
    final controller = StageController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('stage-1', canModerate: true);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stage-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stage-topic-cancel')));
    await tester.pumpAndSettle();

    expect(repository.started, isEmpty);
  });

  testWidgets('a moderator renames and ends the stage', (tester) async {
    final repository = _FakeRepository(
      stage: const StageInstance(
        id: 'i',
        channelId: 'stage-1',
        guildId: 'guild-1',
        topic: 'Before',
      ),
    );
    final controller = StageController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('stage-1', canModerate: true);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stage-moderator-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stage-rename')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('stage-topic-field')),
      'After',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stage-topic-confirm')));
    await tester.pumpAndSettle();

    expect(repository.renamed, ['After']);

    await tester.tap(find.byKey(const ValueKey('stage-moderator-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stage-end')));
    await tester.pumpAndSettle();

    expect(repository.ended, ['stage-1']);
    // With the stage gone, the moderator is offered the way to start another.
    expect(find.byKey(const ValueKey('stage-start')), findsOne);
  });

  testWidgets('submitting the topic from the keyboard works too', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final controller = StageController(() => repository);
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller);
    controller.show('stage-1', canModerate: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stage-start')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('stage-topic-field')),
      'Typed',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(repository.started, ['Typed']);
  });
}

final class _FakeRepository implements StageRepository {
  _FakeRepository({this.stage, this.presence, this.failWrites = false});

  final StreamController<String> _updates = StreamController.broadcast();
  final List<String> requested = [];
  final List<String> cancelled = [];
  final List<bool> speaking = [];
  final List<String> started = [];
  final List<String> renamed = [];
  final List<String> ended = [];
  final List<String> moved = [];
  final bool failWrites;

  StageInstance? stage;
  StagePresence? presence;

  @override
  StageInstance? stageFor(String channelId) =>
      stage?.channelId == channelId ? stage : null;

  @override
  StagePresence? presenceFor(String channelId) =>
      presence?.channelId == channelId ? presence : null;

  @override
  Stream<String> get updates => _updates.stream;

  @override
  Future<void> requestToSpeak(String channelId) async {
    if (failWrites) throw StateError('rejected');
    requested.add(channelId);
    _publish(
      channelId,
      StagePresence(channelId: channelId, requestedAt: DateTime.utc(2026)),
    );
  }

  @override
  Future<void> cancelSpeakRequest(String channelId) async {
    if (failWrites) throw StateError('rejected');
    cancelled.add(channelId);
    _publish(channelId, StagePresence(channelId: channelId));
  }

  @override
  Future<void> setSpeaking(String channelId, {required bool speaking}) async {
    if (failWrites) throw StateError('rejected');
    this.speaking.add(speaking);
    _publish(
      channelId,
      StagePresence(channelId: channelId, isSuppressed: !speaking),
    );
  }

  @override
  Future<void> startStage(
    String channelId, {
    required String topic,
    bool sendStartNotification = false,
  }) async {
    if (failWrites) throw StateError('rejected');
    started.add(topic);
    stage = StageInstance(
      id: 'i',
      channelId: channelId,
      guildId: 'guild-1',
      topic: topic,
    );
    if (!_updates.isClosed) _updates.add(channelId);
  }

  @override
  Future<void> setStageTopic(String channelId, String topic) async {
    if (failWrites) throw StateError('rejected');
    renamed.add(topic);
    stage = StageInstance(
      id: 'i',
      channelId: channelId,
      guildId: 'guild-1',
      topic: topic,
    );
    if (!_updates.isClosed) _updates.add(channelId);
  }

  @override
  Future<void> endStage(String channelId) async {
    if (failWrites) throw StateError('rejected');
    ended.add(channelId);
    stage = null;
    if (!_updates.isClosed) _updates.add(channelId);
  }

  @override
  Future<void> setMemberSpeaking(
    String channelId, {
    required String userId,
    required bool speaking,
  }) async {
    if (failWrites) throw StateError('rejected');
    moved.add(userId);
  }

  void _publish(String channelId, StagePresence value) {
    presence = value;
    if (!_updates.isClosed) _updates.add(channelId);
  }

  Future<void> close() => _updates.close();
}
