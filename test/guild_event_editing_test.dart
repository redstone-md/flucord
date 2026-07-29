import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/guild_event_form_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime.utc(2026, 8, 1, 18);
final _end = DateTime.utc(2026, 8, 1, 20);

GuildScheduledEventDraft _draft({
  String name = 'Forge night',
  GuildScheduledEventEntityType type = GuildScheduledEventEntityType.external,
  String location = 'The workshop',
  String? channelId,
  DateTime? endTime,
  bool withEnd = true,
}) => GuildScheduledEventDraft(
  name: name,
  startTime: _start,
  endTime: !withEnd
      ? null
      : endTime ??
            (type == GuildScheduledEventEntityType.external ? _end : null),
  entityType: type,
  channelId: channelId,
  location: location,
);

void main() {
  group('what Discord will take', () {
    test('an event needs a name and a kind', () {
      expect(_draft().isValid, isTrue);
      expect(_draft(name: '   ').isValid, isFalse);
      expect(
        _draft(type: GuildScheduledEventEntityType.unknown).isValid,
        isFalse,
      );
    });

    test('an event held elsewhere has to say where and when it ends', () {
      // Discord has no channel to infer either from.
      expect(_draft(location: '  ').isValid, isFalse);
      expect(_draft(withEnd: false).isValid, isFalse);
      expect(
        _draft(endTime: _start.subtract(const Duration(hours: 1))).isValid,
        isFalse,
      );
    });

    test('an event in a channel has to name one', () {
      expect(
        _draft(type: GuildScheduledEventEntityType.voice).isValid,
        isFalse,
      );
      expect(
        _draft(
          type: GuildScheduledEventEntityType.voice,
          channelId: 'channel-1',
        ).isValid,
        isTrue,
      );
      // An end is allowed there but must still be after the start.
      expect(
        _draft(
          type: GuildScheduledEventEntityType.stage,
          channelId: 'channel-1',
          endTime: _start.subtract(const Duration(minutes: 1)),
        ).isValid,
        isFalse,
      );
    });

    test('a create sends every field Discord expects', () {
      final body = GuildScheduledEventEdit.encodeDraft(_draft());

      expect(body['name'], 'Forge night');
      expect(body['privacy_level'], 2);
      expect(body['entity_type'], 3);
      expect(body['scheduled_start_time'], _start.toIso8601String());
      expect(body['scheduled_end_time'], _end.toIso8601String());
      // An external event names nowhere on the server and everywhere off it.
      expect(body['channel_id'], isNull);
      expect(body['entity_metadata'], {'location': 'The workshop'});
    });

    test('an event in a channel names the channel, not a location', () {
      final body = GuildScheduledEventEdit.encodeDraft(
        _draft(
          type: GuildScheduledEventEntityType.voice,
          channelId: 'channel-1',
        ),
      );

      expect(body['entity_type'], 2);
      expect(body['channel_id'], 'channel-1');
      expect(body['entity_metadata'], isNull);
      expect(body['scheduled_end_time'], isNull);
    });
  });

  group('who is coming', () {
    test('somebody is named, or named by their id', () {
      const named = GuildScheduledEventAttendee(
        userId: 'user-1',
        displayName: 'Mira',
      );

      expect(named.label, 'Mira');
      expect(
        const GuildScheduledEventAttendee(userId: 'user-2').label,
        'user-2',
      );
      expect(
        named,
        const GuildScheduledEventAttendee(
          userId: 'user-1',
          displayName: 'Mira',
        ),
      );
      expect(
        named.hashCode,
        const GuildScheduledEventAttendee(
          userId: 'user-1',
          displayName: 'Mira',
        ).hashCode,
      );
      expect(
        named == const GuildScheduledEventAttendee(userId: 'user-1'),
        isFalse,
      );
      expect(named == Object(), isFalse);
    });
  });

  group('a partial edit', () {
    test('carries only what was touched', () {
      final edit = GuildScheduledEventEdit();
      expect(edit.isEmpty, isTrue);
      expect(edit.isNotEmpty, isFalse);

      edit
        ..name = 'Renamed'
        ..description = ''
        ..startTime = _start
        ..endTime = _end
        ..channelId = 'channel-2'
        ..location = 'Elsewhere'
        ..status = GuildScheduledEventStatus.canceled;

      expect(edit.isNotEmpty, isTrue);
      expect(edit['name'], 'Renamed');
      // Cleared, not omitted: Discord tells the two apart.
      expect(edit['description'], isEmpty);
      expect(edit['scheduled_start_time'], _start.toIso8601String());
      expect(edit['scheduled_end_time'], _end.toIso8601String());
      expect(edit['channel_id'], 'channel-2');
      expect(edit['entity_metadata'], {'location': 'Elsewhere'});
      // Cancelling is a status change, never a delete.
      expect(edit['status'], 4);
      expect(edit.keys, hasLength(7));
      expect(edit.toJson()['name'], 'Renamed');
    });

    test('clearing the end sends the null rather than dropping the key', () {
      final edit = GuildScheduledEventEdit()..endTime = null;

      expect(edit.keys, ['scheduled_end_time']);
      expect(edit['scheduled_end_time'], isNull);
    });
  });

  group('the form', () {
    testWidgets('a new event will not save until it is complete', (
      tester,
    ) async {
      await _pumpForm(tester);

      expect(_saveEnabled(tester), isFalse);

      await tester.enterText(
        find.byKey(const ValueKey('event-name')),
        'Forge night',
      );
      await tester.pumpAndSettle();
      // An external event still needs somewhere to be.
      expect(_saveEnabled(tester), isFalse);

      await tester.enterText(
        find.byKey(const ValueKey('event-location')),
        'The workshop',
      );
      await tester.pumpAndSettle();

      expect(_saveEnabled(tester), isTrue);
    });

    testWidgets('choosing a channel swaps the location field away', (
      tester,
    ) async {
      await _pumpForm(tester);

      expect(find.byKey(const ValueKey('event-location')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('event-where')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A voice channel').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('event-location')), findsNothing);
      expect(find.byKey(const ValueKey('event-channel')), findsOneWidget);
    });

    testWidgets('a new event hands back a draft', (tester) async {
      GuildEventFormResult? result;
      await _pumpForm(tester, onResult: (value) => result = value);

      await tester.enterText(
        find.byKey(const ValueKey('event-name')),
        'Forge night',
      );
      await tester.enterText(
        find.byKey(const ValueKey('event-location')),
        'The workshop',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      expect(result?.draft?.name, 'Forge night');
      expect(result?.draft?.location, 'The workshop');
      expect(result?.edit, isNull);
      // An external event gets an end even if nobody set one, because Discord
      // refuses one without.
      expect(result?.draft?.endTime, isNotNull);
    });

    testWidgets('an edit sends only the field that moved', (tester) async {
      GuildEventFormResult? result;
      await _pumpForm(
        tester,
        event: _event,
        onResult: (value) => result = value,
      );

      await tester.enterText(
        find.byKey(const ValueKey('event-name')),
        'Renamed',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      expect(result?.edit?.keys, ['name']);
      expect(result?.edit?['name'], 'Renamed');
      expect(result?.draft, isNull);
    });

    testWidgets('an event in a channel hands back the channel it picked', (
      tester,
    ) async {
      GuildEventFormResult? result;
      await _pumpForm(tester, onResult: (value) => result = value);

      await tester.tap(find.byKey(const ValueKey('event-where')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A voice channel').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('event-name')),
        'Forge night',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-channel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workshop').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      expect(result?.draft?.channelId, 'voice-1');
      // A channel event carries no location, whatever was typed before.
      expect(result?.draft?.entityType, GuildScheduledEventEntityType.voice);
    });

    testWidgets('a stage event only offers stage channels', (tester) async {
      await _pumpForm(tester);

      await tester.tap(find.byKey(const ValueKey('event-where')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A stage channel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-channel')));
      await tester.pumpAndSettle();

      // The workshop is an ordinary voice channel, so it is not on offer.
      expect(find.text('Main stage'), findsWidgets);
      expect(find.text('Workshop'), findsNothing);

      await tester.tap(find.text('Main stage').last);
      await tester.pumpAndSettle();
    });

    testWidgets('the start time is picked from a calendar and a clock', (
      tester,
    ) async {
      GuildEventFormResult? result;
      await _pumpForm(tester, onResult: (value) => result = value);

      await tester.tap(find.byKey(const ValueKey('event-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('event-name')),
        'Forge night',
      );
      await tester.enterText(
        find.byKey(const ValueKey('event-location')),
        'The workshop',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      expect(result?.draft?.startTime, isNotNull);
    });

    testWidgets('an edit carries a moved description and location', (
      tester,
    ) async {
      GuildEventFormResult? result;
      await _pumpForm(
        tester,
        event: _event,
        onResult: (value) => result = value,
      );

      await tester.enterText(
        find.byKey(const ValueKey('event-description')),
        'Bring a hammer',
      );
      await tester.enterText(
        find.byKey(const ValueKey('event-location')),
        'The yard',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      expect(result?.edit?.keys, ['description', 'entity_metadata']);
      expect(result?.edit?['entity_metadata'], {'location': 'The yard'});
    });

    testWidgets('an edit that moves the event into a channel says so', (
      tester,
    ) async {
      GuildEventFormResult? result;
      await _pumpForm(
        tester,
        event: _event,
        onResult: (value) => result = value,
      );

      await tester.tap(find.byKey(const ValueKey('event-where')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A voice channel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-channel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workshop').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      // Only the channel moved: an end is allowed on a channel event too, so
      // the one already set is left where it is.
      expect(result?.edit?.keys, ['channel_id']);
      expect(result?.edit?['channel_id'], 'voice-1');
    });

    testWidgets('an end can be cleared on a channel event', (tester) async {
      await _pumpForm(tester, event: _channelEvent);

      expect(find.byKey(const ValueKey('event-end-clear')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-end-clear')));
      await tester.pumpAndSettle();

      expect(find.text('Not set'), findsOneWidget);
    });

    testWidgets('cancelling the form hands nothing back', (tester) async {
      var results = 0;
      await _pumpForm(
        tester,
        onResult: (value) {
          if (value != null) results++;
        },
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(results, 0);
    });

    testWidgets('moving the times carries both of them', (tester) async {
      GuildEventFormResult? result;
      await _pumpForm(
        tester,
        event: _event,
        onResult: (value) => result = value,
      );

      // A different day in the same month, so the start genuinely moves
      // rather than being re-confirmed as itself.
      await tester.tap(find.byKey(const ValueKey('event-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('event-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      expect(result?.edit?.keys, contains('scheduled_start_time'));
      expect(result?.edit?.keys, contains('scheduled_end_time'));
    });

    testWidgets('an edit that changed nothing sends nothing', (tester) async {
      var results = 0;
      await _pumpForm(
        tester,
        event: _event,
        onResult: (value) {
          if (value != null) results++;
        },
      );

      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      expect(results, 0);
    });
  });
}

bool _saveEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('event-save')))
        .onPressed !=
    null;

final _event = GuildScheduledEvent(
  id: '222222222222222222',
  spaceId: '111111111111111111',
  name: 'Forge night',
  scheduledStartTime: _start,
  scheduledEndTime: _end,
  entityType: GuildScheduledEventEntityType.external,
  status: GuildScheduledEventStatus.scheduled,
  location: 'The workshop',
);

final _channelEvent = GuildScheduledEvent(
  id: '333333333333333333',
  spaceId: '111111111111111111',
  name: 'Workshop hours',
  scheduledStartTime: _start,
  scheduledEndTime: _end,
  entityType: GuildScheduledEventEntityType.voice,
  status: GuildScheduledEventStatus.scheduled,
  channelId: 'voice-1',
);

Future<void> _pumpForm(
  WidgetTester tester, {
  GuildScheduledEvent? event,
  ValueChanged<GuildEventFormResult?>? onResult,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-form'),
            onPressed: () async {
              final result = await showDialog<GuildEventFormResult>(
                context: context,
                builder: (_) => GuildEventFormDialog(
                  channels: const [
                    ConversationChannel(
                      id: 'voice-1',
                      spaceId: '111111111111111111',
                      name: 'Workshop',
                      topic: '',
                      kind: ChannelKind.voice,
                    ),
                    ConversationChannel(
                      id: 'stage-1',
                      spaceId: '111111111111111111',
                      name: 'Main stage',
                      topic: '',
                      kind: ChannelKind.voice,
                      isStage: true,
                    ),
                  ],
                  event: event,
                ),
              );
              onResult?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-form')));
  await tester.pumpAndSettle();
}
