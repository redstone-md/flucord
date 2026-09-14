import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime.utc(2026, 8, 1, 18);

GuildScheduledEvent _event({
  List<GuildScheduledEventException> exceptions = const [],
}) => GuildScheduledEvent(
  id: 'event-1',
  spaceId: 'guild-1',
  name: 'Forge night',
  scheduledStartTime: _start,
  entityType: GuildScheduledEventEntityType.external,
  status: GuildScheduledEventStatus.scheduled,
  coverImageHash: 'a1b2c3',
  recurrence: EventRecurrenceRule(
    start: _start,
    frequency: EventRecurrenceFrequency.weekly,
  ),
  exceptions: exceptions,
);

const _moved = GuildScheduledEventException(
  id: 'exception-1',
  eventId: 'event-1',
  spaceId: 'guild-1',
);

void main() {
  group('reading one', () {
    test('an exception says what changed about the occurrence', () {
      final exception = GuildScheduledEventException.fromJson({
        'event_exception_id': 'exception-1',
        'event_id': 'event-1',
        'guild_id': 'guild-1',
        'scheduled_start_time': '2026-08-08T19:00:00+00:00',
        'scheduled_end_time': '2026-08-08T21:00:00+00:00',
        'is_canceled': false,
      })!;

      expect(exception.id, 'exception-1');
      expect(exception.eventId, 'event-1');
      expect(exception.spaceId, 'guild-1');
      expect(exception.scheduledStartTime, DateTime.utc(2026, 8, 8, 19));
      expect(exception.scheduledEndTime, DateTime.utc(2026, 8, 8, 21));
      expect(exception.isCanceled, isFalse);
      expect(exception.describe(), 'One occurrence moved');
    });

    test('a cancelled occurrence says so, and a bare one says less', () {
      expect(
        GuildScheduledEventException.fromJson(const {
          'event_exception_id': 'exception-1',
          'event_id': 'event-1',
          'is_canceled': true,
        })!.describe(),
        'One occurrence is cancelled',
      );
      expect(
        GuildScheduledEventException.fromJson(const {
          'event_exception_id': 'exception-1',
          'event_id': 'event-1',
        })!.describe(),
        'One occurrence differs',
      );
    });

    test('an exception naming no occurrence is not one', () {
      expect(GuildScheduledEventException.fromJson(null), isNull);
      expect(GuildScheduledEventException.fromJson('nonsense'), isNull);
      expect(
        GuildScheduledEventException.fromJson(const {'event_id': 'event-1'}),
        isNull,
      );
      expect(
        GuildScheduledEventException.fromJson(const {
          'event_exception_id': 'exception-1',
        }),
        isNull,
      );
      expect(
        GuildScheduledEventException.fromJson(const {
          'event_exception_id': '',
          'event_id': 'event-1',
        }),
        isNull,
      );
    });

    test('a time Discord did not send is left absent', () {
      final exception = GuildScheduledEventException.fromJson(const {
        'event_exception_id': 'exception-1',
        'event_id': 'event-1',
        'scheduled_start_time': 'not a time',
        'scheduled_end_time': '',
      })!;

      expect(exception.scheduledStartTime, isNull);
      expect(exception.scheduledEndTime, isNull);
    });

    test('an exception compares by what it says', () {
      expect(
        _moved,
        const GuildScheduledEventException(
          id: 'exception-1',
          eventId: 'event-1',
          spaceId: 'guild-1',
        ),
      );
      expect(
        _moved.hashCode,
        const GuildScheduledEventException(
          id: 'exception-1',
          eventId: 'event-1',
          spaceId: 'guild-1',
        ).hashCode,
      );
      expect(
        _moved ==
            const GuildScheduledEventException(
              id: 'exception-1',
              eventId: 'event-1',
            ),
        isFalse,
      );
      expect(_moved == Object(), isFalse);
    });
  });

  group('folding them into an event', () {
    test('an event reads the exceptions it arrived with', () {
      final event = _event(exceptions: const [_moved]);

      expect(event.exceptions.single.id, 'exception-1');
      expect(event.repeats, isTrue);
    });

    test('an exception replaces the one it is for', () {
      const revised = GuildScheduledEventException(
        id: 'exception-1',
        eventId: 'event-1',
        isCanceled: true,
      );

      final folded = _event(exceptions: const [_moved]).withException(revised);

      expect(folded.exceptions.single.isCanceled, isTrue);
      // Everything else about the event survives the fold.
      expect(folded.coverImageHash, 'a1b2c3');
      expect(folded.recurrence, isNotNull);
    });

    test('a second exception joins rather than replaces', () {
      const other = GuildScheduledEventException(
        id: 'exception-2',
        eventId: 'event-1',
      );

      final folded = _event(exceptions: const [_moved]).withException(other);

      expect(folded.exceptions.map((e) => e.id), [
        'exception-1',
        'exception-2',
      ]);
    });

    test('a deleted exception puts that occurrence back to the rule', () {
      final folded = _event(
        exceptions: const [_moved],
      ).withoutException('exception-1');

      expect(folded.exceptions, isEmpty);
      expect(folded.coverImageHash, 'a1b2c3');
    });

    test('a delete of something not held changes nothing', () {
      final folded = _event(
        exceptions: const [_moved],
      ).withoutException('exception-9');

      expect(folded.exceptions.single.id, 'exception-1');
    });

    test('clearing the series drops every exception at once', () {
      final event = _event(exceptions: const [_moved]);

      expect(event.withoutExceptions().exceptions, isEmpty);
      // An event with none already is handed back as it is.
      expect(
        identical(_event().withoutExceptions(), _event().withoutExceptions()),
        isFalse,
      );
      final none = _event();
      expect(identical(none.withoutExceptions(), none), isTrue);
    });

    test('the exceptions survive a count change', () {
      final event = _event(exceptions: const [_moved]);

      // The RSVP dispatch rebuilds the row through copyWith; exceptions lost
      // there would vanish the moment anybody said they were interested.
      expect(event.copyWith(interestedCount: 4).exceptions, hasLength(1));
    });
  });
}
