part of 'chat_models.dart';

/// How often an event repeats.
///
/// The codes are Discord's. The three it never offers a guild event — hourly,
/// minutely, secondly — are absent rather than listed and refused, because a
/// choice nobody can make is not a choice.
enum EventRecurrenceFrequency {
  yearly(0),
  monthly(1),
  weekly(2),
  daily(3);

  const EventRecurrenceFrequency(this.discordValue);

  final int discordValue;

  static EventRecurrenceFrequency? fromCode(Object? code) {
    for (final value in values) {
      if (value.discordValue == code) return value;
    }
    return null;
  }
}

/// The rule that says when an event happens again.
///
/// Discord replaces the whole rule on every write, so the parts this build has
/// no control for are carried through untouched rather than dropped: editing
/// the name of an event that repeats on the second Tuesday must not quietly
/// turn it into one that repeats every Tuesday.
final class EventRecurrenceRule {
  const EventRecurrenceRule({
    required this.start,
    required this.frequency,
    this.interval = 1,
    this.byWeekday = const [],
    this.count,
    this.end,
    this.unmodelled = const {},
  });

  /// When the repetition is anchored. Discord sets this to the first
  /// occurrence and it is not the same as the event's own start once an
  /// occurrence has been moved.
  final DateTime start;

  final EventRecurrenceFrequency frequency;

  /// Every nth day, week, month or year. Discord's own floor is one.
  final int interval;

  /// Days of the week, as Discord numbers them: Monday is 0.
  final List<int> byWeekday;

  /// How many times in total, or null for no limit.
  final int? count;

  /// When it stops, or null for no end.
  final DateTime? end;

  /// The parts of the rule this build shows no control for — `by_n_weekday`,
  /// `by_month`, `by_month_day`, `by_year_day` — kept exactly as Discord sent
  /// them so a write does not erase what a write did not touch.
  final Map<String, Object?> unmodelled;

  /// One line naming the rule, for a surface that has room for one.
  String get summary {
    final every = interval == 1 ? '' : ' $interval';
    final unit = switch (frequency) {
      EventRecurrenceFrequency.daily => interval == 1 ? 'day' : 'days',
      EventRecurrenceFrequency.weekly => interval == 1 ? 'week' : 'weeks',
      EventRecurrenceFrequency.monthly => interval == 1 ? 'month' : 'months',
      EventRecurrenceFrequency.yearly => interval == 1 ? 'year' : 'years',
    };
    return 'Repeats every$every $unit';
  }

  Map<String, Object?> toJson() => {
    'start': start.toUtc().toIso8601String(),
    'end': end?.toUtc().toIso8601String(),
    'frequency': frequency.discordValue,
    'interval': interval < 1 ? 1 : interval,
    'by_weekday': byWeekday.isEmpty ? null : byWeekday,
    'count': count,
    ...unmodelled,
  };

  /// Reads a rule, or null when the event does not repeat.
  static EventRecurrenceRule? fromJson(Object? payload) {
    if (payload is! Map) return null;
    final fields = payload.cast<String, Object?>();
    final frequency = EventRecurrenceFrequency.fromCode(fields['frequency']);
    final start = fields['start'];
    if (frequency == null || start is! String) return null;
    final parsedStart = DateTime.tryParse(start);
    if (parsedStart == null) return null;
    return EventRecurrenceRule(
      start: parsedStart.toUtc(),
      frequency: frequency,
      interval: switch (fields['interval']) {
        final int value when value > 0 => value,
        _ => 1,
      },
      byWeekday: [
        for (final day in _list(fields['by_weekday']))
          if (day is int) day,
      ],
      count: fields['count'] is int ? fields['count']! as int : null,
      end: fields['end'] is String
          ? DateTime.tryParse(fields['end']! as String)?.toUtc()
          : null,
      unmodelled: {
        for (final key in const [
          'by_n_weekday',
          'by_month',
          'by_month_day',
          'by_year_day',
        ])
          if (fields[key] != null) key: fields[key],
      },
    );
  }

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  @override
  bool operator ==(Object other) =>
      other is EventRecurrenceRule &&
      other.start == start &&
      other.frequency == frequency &&
      other.interval == interval &&
      other.count == count &&
      other.end == end &&
      other.byWeekday.join(',') == byWeekday.join(',');

  @override
  int get hashCode =>
      Object.hash(start, frequency, interval, count, end, byWeekday.join(','));
}
