import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/message_search_grammar.dart';
import 'package:flucord/src/data/discord/discord_snowflake.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/message_search.dart';

/// The search bar's grammar decides what Discord is actually asked, so a
/// mis-parsed token is a search that quietly answers a different question.
void main() {
  test('keeps unfiltered words as the content bucket', () {
    final parse = _grammar().parse('  release   notes  ');

    expect(parse.filters.content, 'release notes');
    expect(parse.isEmpty, isFalse);
    expect(parse.unresolved, isEmpty);
  });

  test('resolves from: and mentions: by name, @me and raw id', () {
    final parse = _grammar().parse(
      'from:Ada from:@me mentions:"@Grace Hopper" '
      'mentions:987654321098765432 notes',
    );

    expect(parse.filters.authorIds, const [
      '123456789012345678',
      '333333333333333333',
      '111111111111111111',
    ]);
    expect(parse.filters.mentionIds, const [
      '234567890123456789',
      '987654321098765432',
    ]);
    expect(parse.filters.content, 'notes');
  });

  test('keeps every person who answers to the same display name', () {
    final parse = _grammar().parse('from:ada');

    expect(parse.filters.authorIds, const [
      '123456789012345678',
      '333333333333333333',
    ]);
  });

  test('resolves in: by name, by id, and only inside what is readable', () {
    final parse = _grammar().parse('in:#release in:222222222222222222');

    expect(parse.filters.channelIds, const [
      '111111111111111111',
      '222222222222222222',
    ]);
    expect(parse.unresolved, isEmpty);
  });

  test('reports filters this workspace cannot resolve', () {
    final parse = _grammar().parse(
      'from:nobody in:#hidden in:987654321098765432 has:telepathy pinned:maybe '
      'before:not-a-date',
    );

    expect(parse.filters.authorIds, isEmpty);
    expect(parse.filters.channelIds, isEmpty);
    expect(parse.filters.has, isEmpty);
    expect(parse.filters.pinned, isNull);
    expect(parse.filters.maxId, isNull);
    // Reported rather than dropped: a filter the server never receives would
    // silently widen the search.
    expect(parse.unresolved, const [
      'from:nobody',
      'in:#hidden',
      'in:987654321098765432',
      'has:telepathy',
      'pinned:maybe',
      'before:not-a-date',
    ]);
    expect(parse.isEmpty, isTrue);
  });

  test('parses has: including negation, and de-duplicates', () {
    final parse = _grammar().parse('has:image has:image has:-video');

    expect(parse.filters.has, const [
      MessageSearchHas(MessageSearchHasKind.image),
      MessageSearchHas(MessageSearchHasKind.video, negated: true),
    ]);
    expect(parse.filters.has.first.wireValue, 'image');
    expect(parse.filters.has.last.wireValue, '-video');
  });

  test('parses pinned: either way', () {
    expect(_grammar().parse('pinned:true').filters.pinned, isTrue);
    expect(_grammar().parse('pinned:FALSE').filters.pinned, isFalse);
  });

  test('turns before: and after: into snowflake bounds', () {
    final parse = _grammar().parse('after:2024-05-01 before:2024-06-01');

    expect(
      parse.filters.minId,
      DiscordSnowflake.fromTimestampMillis(
        DateTime(2024, 5, 2).millisecondsSinceEpoch,
      ),
    );
    expect(
      parse.filters.maxId,
      DiscordSnowflake.fromTimestampMillis(
        DateTime(2024, 6).millisecondsSinceEpoch,
      ),
    );
  });

  test('accepts a month and a year as whole buckets', () {
    final month = _grammar().parse('before:2024-06').filters;
    expect(
      month.maxId,
      DiscordSnowflake.fromTimestampMillis(
        DateTime(2024, 6).millisecondsSinceEpoch,
      ),
    );

    final year = _grammar().parse('after:2024').filters;
    expect(
      year.minId,
      DiscordSnowflake.fromTimestampMillis(
        DateTime(2025).millisecondsSinceEpoch,
      ),
    );
  });

  test('rejects a date that is not the day it names', () {
    final parse = _grammar().parse(
      'before:2024-02-31 after:2024-13-01 '
      'before:2024-01-00',
    );

    expect(parse.filters.maxId, isNull);
    expect(parse.filters.minId, isNull);
    expect(parse.unresolved, hasLength(3));
  });

  test('a later date token replaces the earlier one', () {
    final parse = _grammar().parse('before:2024-05-01 before:2023-01-01');

    expect(
      parse.filters.maxId,
      DiscordSnowflake.fromTimestampMillis(
        DateTime(2023).millisecondsSinceEpoch,
      ),
    );
  });

  test('quotes hold a filter answer together and hide its colons', () {
    final parse = _grammar().parse(r'from:"Grace Hopper" "12:30" a\b');

    expect(parse.filters.authorIds, const ['234567890123456789']);
    expect(parse.filters.content, r'12:30 a\b');
  });

  test('unescapes a quoted answer the way the bar serialises it', () {
    final parse = _grammar().parse(r'"say \"hi\" \\ now"');

    expect(parse.filters.content, r'say "hi" \ now');
  });

  test('strips a filter word with no answer', () {
    final parse = _grammar().parse('from: notes');

    expect(parse.filters.authorIds, isEmpty);
    expect(parse.filters.content, 'notes');
  });

  test('a colon after an unknown word stays free text', () {
    final parse = _grammar().parse('note:this :leading');

    expect(parse.filters.content, 'note:this :leading');
  });

  test('an empty bar resolves to nothing to ask about', () {
    final parse = _grammar().parse('   ');

    expect(parse.isEmpty, isTrue);
    expect(parse.filters.content, isEmpty);
  });

  test('an empty quoted answer is not a filter either', () {
    expect(_grammar().parse('""').filters.isEmpty, isTrue);
  });
}

MessageSearchGrammar _grammar() => const MessageSearchGrammar(
  channels: [
    ConversationChannel(
      id: '111111111111111111',
      spaceId: '333333333333333333',
      name: 'release',
      topic: '',
      kind: ChannelKind.text,
    ),
    ConversationChannel(
      id: '222222222222222222',
      spaceId: '333333333333333333',
      name: 'native-client',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  members: [
    Member(
      id: '123456789012345678',
      displayName: 'Ada',
      initials: 'A',
      role: 'Engineer',
      presence: Presence.online,
      colorValue: 0xff456b5a,
    ),
    Member(
      id: '234567890123456789',
      displayName: 'Grace Hopper',
      initials: 'GH',
      role: 'Engineer',
      presence: Presence.online,
      colorValue: 0xff456b5a,
    ),
    Member(
      id: '333333333333333333',
      displayName: 'ada',
      initials: 'A',
      role: 'Engineer',
      presence: Presence.offline,
      colorValue: 0xff456b5a,
    ),
  ],
  currentMemberId: '111111111111111111',
);
