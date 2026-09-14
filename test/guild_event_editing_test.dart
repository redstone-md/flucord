import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/profile_image_picker.dart';
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
  String? cover,
  EventRecurrenceRule? recurrence,
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
  coverImage: cover,
  recurrence: recurrence,
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

  group('the cover', () {
    test('a create carries one only when there is one', () {
      expect(
        GuildScheduledEventEdit.encodeDraft(_draft()).containsKey('image'),
        isFalse,
      );
      expect(
        GuildScheduledEventEdit.encodeDraft(
          _draft(cover: 'data:image/png;base64,AAAA'),
        )['image'],
        'data:image/png;base64,AAAA',
      );
    });

    test('an edit tells an absent cover from a cleared one', () {
      final cleared = GuildScheduledEventEdit()..coverImage = null;
      expect(cleared.keys, ['image']);
      expect(cleared['image'], isNull);

      final replaced = GuildScheduledEventEdit()
        ..coverImage = 'data:image/png;base64,AAAA';
      expect(replaced['image'], 'data:image/png;base64,AAAA');
    });

    test('a CDN hash is refused where a picture was asked for', () {
      // The server has no use for the name it gave us; sending it back would
      // ask Discord to store its own filename as an image.
      expect(
        () => GuildScheduledEventEdit()..coverImage = 'a1b2c3',
        throwsArgumentError,
      );
    });

    test('an event keeps its cover through a count change', () {
      final event = GuildScheduledEvent(
        id: 'event-1',
        spaceId: 'forge',
        name: 'Forge night',
        scheduledStartTime: _start,
        entityType: GuildScheduledEventEntityType.external,
        status: GuildScheduledEventStatus.scheduled,
        coverImageHash: 'a1b2c3',
      );

      // The RSVP dispatch moves the count through copyWith; a cover dropped
      // there would vanish the moment anybody said they were interested.
      expect(event.copyWith(interestedCount: 5).coverImageHash, 'a1b2c3');
    });
  });

  group('choosing a cover', () {
    testWidgets('a chosen cover reaches the draft', (tester) async {
      GuildEventFormResult? result;
      await _pumpForm(
        tester,
        picker: _FakePicker('data:image/png;base64,AAAA'),
        onResult: (value) => result = value,
      );

      expect(find.text('No cover'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-cover-pick')));
      await tester.pumpAndSettle();
      expect(find.text('Cover chosen'), findsOneWidget);

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

      expect(result?.draft?.coverImage, 'data:image/png;base64,AAAA');
    });

    testWidgets('cancelling the picker leaves the cover alone', (tester) async {
      await _pumpForm(tester, picker: _FakePicker(null));

      await tester.tap(find.byKey(const ValueKey('event-cover-pick')));
      await tester.pumpAndSettle();

      expect(find.text('No cover'), findsOneWidget);
    });

    testWidgets('an event with a cover says so, and can drop it', (
      tester,
    ) async {
      GuildEventFormResult? result;
      await _pumpForm(
        tester,
        event: _coveredEvent,
        onResult: (value) => result = value,
      );

      expect(find.text('Cover set'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-cover-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Cover will be removed'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      expect(result?.edit?.keys, ['image']);
      expect(result?.edit?['image'], isNull);
    });

    testWidgets('a replaced cover is sent as the new picture', (tester) async {
      GuildEventFormResult? result;
      await _pumpForm(
        tester,
        event: _coveredEvent,
        picker: _FakePicker('data:image/png;base64,BBBB'),
        onResult: (value) => result = value,
      );

      await tester.tap(find.byKey(const ValueKey('event-cover-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      expect(result?.edit?.keys, ['image']);
      expect(result?.edit?['image'], 'data:image/png;base64,BBBB');
    });

    testWidgets('an edit that touched no cover sends no image', (tester) async {
      GuildEventFormResult? result;
      await _pumpForm(
        tester,
        event: _coveredEvent,
        onResult: (value) => result = value,
      );

      await tester.enterText(
        find.byKey(const ValueKey('event-name')),
        'Renamed',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      // Absent means untouched; collapsing it into "cleared" would drop
      // somebody's cover every time they renamed an event.
      expect(result?.edit?.keys, ['name']);
    });

    testWidgets('a new event can drop a cover it just chose', (tester) async {
      await _pumpForm(
        tester,
        picker: _FakePicker('data:image/png;base64,AAAA'),
      );

      await tester.tap(find.byKey(const ValueKey('event-cover-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-cover-clear')));
      await tester.pumpAndSettle();

      expect(find.text('Cover will be removed'), findsOneWidget);
    });
  });

  group('repeating', () {
    test('a rule reads back everything Discord sent', () {
      final rule = EventRecurrenceRule.fromJson({
        'start': '2026-08-01T18:00:00+00:00',
        'end': '2026-12-01T18:00:00+00:00',
        'frequency': 2,
        'interval': 2,
        'by_weekday': [0, 2, 'nonsense'],
        'count': 10,
        'by_n_weekday': [
          {'n': 2, 'day': 1},
        ],
        'by_month': [8],
      })!;

      expect(rule.frequency, EventRecurrenceFrequency.weekly);
      expect(rule.interval, 2);
      expect(rule.byWeekday, [0, 2]);
      expect(rule.count, 10);
      expect(rule.end, DateTime.utc(2026, 12, 1, 18));
      // The parts with no control here are kept exactly as they arrived.
      expect(rule.unmodelled, {
        'by_n_weekday': [
          {'n': 2, 'day': 1},
        ],
        'by_month': [8],
      });
      expect(rule.summary, 'Repeats every 2 weeks');
    });

    test('an event that does not repeat has no rule', () {
      expect(EventRecurrenceRule.fromJson(null), isNull);
      expect(EventRecurrenceRule.fromJson('nonsense'), isNull);
      // A frequency Discord does not offer a guild event is not a rule here.
      expect(
        EventRecurrenceRule.fromJson(const {
          'start': '2026-08-01T18:00:00+00:00',
          'frequency': 5,
        }),
        isNull,
      );
      expect(EventRecurrenceRule.fromJson(const {'frequency': 3}), isNull);
      expect(
        EventRecurrenceRule.fromJson(const {
          'start': 'not a time',
          'frequency': 3,
        }),
        isNull,
      );
    });

    test('an interval Discord would refuse is floored at one', () {
      final zero = EventRecurrenceRule.fromJson(const {
        'start': '2026-08-01T18:00:00+00:00',
        'frequency': 3,
        'interval': 0,
      })!;

      expect(zero.interval, 1);
      expect(zero.summary, 'Repeats every day');
      expect(zero.toJson()['interval'], 1);
      expect(zero.toJson()['by_weekday'], isNull);
    });

    test('every frequency says how it reads', () {
      String summaryOf(EventRecurrenceFrequency frequency, int interval) =>
          EventRecurrenceRule(
            start: DateTime.utc(2026, 8),
            frequency: frequency,
            interval: interval,
          ).summary;

      expect(summaryOf(EventRecurrenceFrequency.daily, 1), 'Repeats every day');
      expect(
        summaryOf(EventRecurrenceFrequency.daily, 3),
        'Repeats every 3 days',
      );
      expect(
        summaryOf(EventRecurrenceFrequency.weekly, 1),
        'Repeats every week',
      );
      expect(
        summaryOf(EventRecurrenceFrequency.monthly, 2),
        'Repeats every 2 months',
      );
      expect(
        summaryOf(EventRecurrenceFrequency.monthly, 1),
        'Repeats every month',
      );
      expect(
        summaryOf(EventRecurrenceFrequency.yearly, 1),
        'Repeats every year',
      );
      expect(
        summaryOf(EventRecurrenceFrequency.yearly, 5),
        'Repeats every 5 years',
      );
      expect(
        summaryOf(EventRecurrenceFrequency.weekly, 4),
        'Repeats every 4 weeks',
      );
    });

    test('a rule compares by what it says', () {
      final rule = EventRecurrenceRule(
        start: DateTime.utc(2026, 8),
        frequency: EventRecurrenceFrequency.weekly,
        byWeekday: const [0],
      );

      expect(
        rule,
        EventRecurrenceRule(
          start: DateTime.utc(2026, 8),
          frequency: EventRecurrenceFrequency.weekly,
          byWeekday: const [0],
        ),
      );
      expect(
        rule.hashCode,
        EventRecurrenceRule(
          start: DateTime.utc(2026, 8),
          frequency: EventRecurrenceFrequency.weekly,
          byWeekday: const [0],
        ).hashCode,
      );
      expect(
        rule ==
            EventRecurrenceRule(
              start: DateTime.utc(2026, 8),
              frequency: EventRecurrenceFrequency.weekly,
            ),
        isFalse,
      );
      expect(rule == Object(), isFalse);
      expect(EventRecurrenceFrequency.fromCode('nonsense'), isNull);
    });

    test('a create carries the rule, and null when there is none', () {
      final withRule = GuildScheduledEventEdit.encodeDraft(
        _draft(
          recurrence: EventRecurrenceRule(
            start: DateTime.utc(2026, 8),
            frequency: EventRecurrenceFrequency.daily,
          ),
        ),
      );

      expect((withRule['recurrence_rule']! as Map)['frequency'], 3);
      expect(
        GuildScheduledEventEdit.encodeDraft(_draft())['recurrence_rule'],
        isNull,
      );
    });

    test('an edit can stop an event repeating', () {
      final stopped = GuildScheduledEventEdit()..recurrence = null;

      expect(stopped.keys, ['recurrence_rule']);
      expect(stopped['recurrence_rule'], isNull);
    });
  });

  group('choosing how often', () {
    testWidgets('a new event can be made to repeat', (tester) async {
      GuildEventFormResult? result;
      await _pumpForm(tester, onResult: (value) => result = value);

      await tester.tap(find.byKey(const ValueKey('event-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Every week').last);
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

      expect(
        result?.draft?.recurrence?.frequency,
        EventRecurrenceFrequency.weekly,
      );
    });

    testWidgets('changing how often keeps the parts with no control', (
      tester,
    ) async {
      GuildEventFormResult? result;
      await _pumpForm(
        tester,
        event: _repeatingEvent,
        onResult: (value) => result = value,
      );

      await tester.tap(find.byKey(const ValueKey('event-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Every month').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      final rule = result!.edit!['recurrence_rule']! as Map;
      expect(rule['frequency'], 1);
      // Editing when it repeats must not quietly rewrite the rest of the rule.
      expect(rule['by_n_weekday'], [
        {'n': 2, 'day': 1},
      ]);
      expect(rule['interval'], 2);
    });

    testWidgets('an event can be made to stop repeating', (tester) async {
      GuildEventFormResult? result;
      await _pumpForm(
        tester,
        event: _repeatingEvent,
        onResult: (value) => result = value,
      );

      await tester.tap(find.byKey(const ValueKey('event-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Does not repeat').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await tester.pumpAndSettle();

      expect(result?.edit?.keys, ['recurrence_rule']);
      expect(result?.edit?['recurrence_rule'], isNull);
    });

    testWidgets('leaving the rule alone sends no rule', (tester) async {
      GuildEventFormResult? result;
      await _pumpForm(
        tester,
        event: _repeatingEvent,
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

final _repeatingEvent = GuildScheduledEvent(
  id: '555555555555555555',
  spaceId: '111111111111111111',
  name: 'Forge night',
  scheduledStartTime: _start,
  scheduledEndTime: _end,
  entityType: GuildScheduledEventEntityType.external,
  status: GuildScheduledEventStatus.scheduled,
  location: 'The workshop',
  recurrence: EventRecurrenceRule(
    start: _start,
    frequency: EventRecurrenceFrequency.weekly,
    interval: 2,
    unmodelled: const {
      'by_n_weekday': [
        {'n': 2, 'day': 1},
      ],
    },
  ),
);

final _coveredEvent = GuildScheduledEvent(
  id: '444444444444444444',
  spaceId: '111111111111111111',
  name: 'Forge night',
  scheduledStartTime: _start,
  scheduledEndTime: _end,
  entityType: GuildScheduledEventEntityType.external,
  status: GuildScheduledEventStatus.scheduled,
  location: 'The workshop',
  coverImageHash: 'a1b2c3',
);

/// Answers the picker without a file dialog.
final class _FakePicker implements ProfileImagePicker {
  const _FakePicker(this._dataUri);

  final String? _dataUri;

  @override
  Future<ProfileImageSelection?> pick() async => _dataUri == null
      ? null
      : ProfileImageSelection(
          dataUri: _dataUri,
          name: 'cover.png',
          byteCount: 4,
        );
}

Future<void> _pumpForm(
  WidgetTester tester, {
  GuildScheduledEvent? event,
  ValueChanged<GuildEventFormResult?>? onResult,
  ProfileImagePicker? picker,
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
                  imagePicker: picker ?? _FakePicker(null),
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
