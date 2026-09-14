import 'package:flucord/src/data/discord/discord_conversation_summary_service.dart';
import 'package:flucord/src/domain/conversation_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ids in ascending order, so a test can say which stretch is older. Kept
/// deliberately short: a full-width snowflake in a fixture is indistinguishable
/// from a real one, and the privacy audit refuses the repository over it.
const _older = '1001';
const _newer = '2002';
const _newest = '3003';

Map<String, Object?> _summary({
  required String id,
  String start = _older,
  String topic = 'deployment',
  String text = 'They agreed to ship on Friday.',
  List<Object?> people = const ['user-1'],
  int count = 12,
}) => {
  'id': id,
  'topic': topic,
  'summ_short': text,
  'people': people,
  'start_id': start,
  'end_id': _newest,
  'count': count,
};

void main() {
  test('reads what a dispatch carries', () {
    final service = DiscordConversationSummaryService();
    addTearDown(service.close);

    expect(
      service.accept('CONVERSATION_SUMMARY_UPDATE', {
        'channel_id': 'channel-1',
        'guild_id': 'guild-1',
        'summaries': [
          _summary(id: 's1', people: const ['user-1', 'user-2', 'user-1', 7]),
        ],
      }),
      'channel-1',
    );

    final summary = service.summariesFor('channel-1').single;
    expect(summary.id, 's1');
    expect(summary.channelId, 'channel-1');
    expect(summary.topic, 'deployment');
    expect(summary.summary, 'They agreed to ship on Friday.');
    // Discord repeats somebody who spoke in several stretches of one summary.
    expect(summary.participantIds, ['user-1', 'user-2']);
    expect(summary.startMessageId, _older);
    expect(summary.endMessageId, _newest);
    expect(summary.messageCount, 12);
    expect(summary.isEmpty, isFalse);
  });

  test('orders by where each stretch starts, newest first', () {
    final service = DiscordConversationSummaryService();
    addTearDown(service.close);

    service.accept('CONVERSATION_SUMMARY_UPDATE', {
      'channel_id': 'channel-1',
      'summaries': [
        _summary(id: 'old', start: _older),
        _summary(id: 'new', start: _newest),
        _summary(id: 'mid', start: _newer),
      ],
    });

    expect(service.summariesFor('channel-1').map((s) => s.id), [
      'new',
      'mid',
      'old',
    ]);
  });

  test('a later dispatch merges rather than replacing the channel', () {
    final service = DiscordConversationSummaryService();
    addTearDown(service.close);
    service.accept('CONVERSATION_SUMMARY_UPDATE', {
      'channel_id': 'channel-1',
      'summaries': [_summary(id: 'first', start: _older)],
    });

    service.accept('CONVERSATION_SUMMARY_UPDATE', {
      'channel_id': 'channel-1',
      'summaries': [
        _summary(id: 'second', start: _newest),
        // The same stretch again, revised.
        _summary(id: 'first', start: _older, topic: 'rewritten'),
      ],
    });

    final summaries = service.summariesFor('channel-1');
    expect(summaries.map((s) => s.id), ['second', 'first']);
    // Revised, not duplicated.
    expect(summaries.last.topic, 'rewritten');
  });

  test('a summary with nothing written yet is not shown', () {
    final service = DiscordConversationSummaryService();
    addTearDown(service.close);

    expect(
      service.accept('CONVERSATION_SUMMARY_UPDATE', {
        'channel_id': 'channel-1',
        'summaries': [
          {'id': 's1', 'topic': '', 'summ_short': ''},
          {'topic': 'no id'},
        ],
      }),
      isNull,
    );
    expect(service.summariesFor('channel-1'), isEmpty);
  });

  test('keeps at most what the desktop client keeps', () {
    final service = DiscordConversationSummaryService();
    addTearDown(service.close);
    final many = [
      for (var index = 0; index < 90; index++)
        _summary(id: 's$index', start: '${1000 + index}'),
    ];

    service.accept('CONVERSATION_SUMMARY_UPDATE', {
      'channel_id': 'channel-1',
      'summaries': many,
    });

    final kept = service.summariesFor('channel-1');
    expect(kept.length, DiscordConversationSummaryService.retainedPerChannel);
    // The newest survive; the oldest fall off the end.
    expect(kept.first.id, 's89');
    expect(kept.last.id, 's15');
  });

  test('summaries with no start id fall back to their own order', () {
    final service = DiscordConversationSummaryService();
    addTearDown(service.close);

    service.accept('CONVERSATION_SUMMARY_UPDATE', {
      'channel_id': 'channel-1',
      'summaries': [
        {'id': _older, 'topic': 'a', 'summ_short': 'first'},
        {'id': _newest, 'topic': 'b', 'summ_short': 'second'},
      ],
    });

    expect(service.summariesFor('channel-1').first.id, _newest);
  });

  test('channels are kept apart', () {
    final service = DiscordConversationSummaryService();
    addTearDown(service.close);

    service
      ..accept('CONVERSATION_SUMMARY_UPDATE', {
        'channel_id': 'channel-1',
        'summaries': [_summary(id: 's1')],
      })
      ..accept('CONVERSATION_SUMMARY_UPDATE', {
        'channel_id': 'channel-2',
        'summaries': [_summary(id: 's2')],
      });

    expect(service.summariesFor('channel-1').single.id, 's1');
    expect(service.summariesFor('channel-2').single.id, 's2');
    // A channel nobody has been told about has none rather than null.
    expect(service.summariesFor('channel-9'), isEmpty);
  });

  test('publishes the channel that changed', () async {
    final service = DiscordConversationSummaryService();
    final seen = <String>[];
    final subscription = service.updates.listen(seen.add);
    addTearDown(subscription.cancel);

    service.accept('CONVERSATION_SUMMARY_UPDATE', {
      'channel_id': 'channel-1',
      'summaries': [_summary(id: 's1')],
    });
    await Future<void>.delayed(Duration.zero);

    expect(seen, ['channel-1']);

    await service.close();
    // Closing twice is what a repository shutdown does when it is retried.
    await service.close();
    expect(
      service.accept('CONVERSATION_SUMMARY_UPDATE', {
        'channel_id': 'channel-1',
        'summaries': [_summary(id: 's2')],
      }),
      'channel-1',
    );
  });

  test('anything else changes nothing', () {
    final service = DiscordConversationSummaryService();
    addTearDown(service.close);

    expect(service.accept('MESSAGE_CREATE', const {}), isNull);
    expect(service.accept('CONVERSATION_SUMMARY_UPDATE', const {}), isNull);
    expect(
      service.accept('CONVERSATION_SUMMARY_UPDATE', const {
        'channel_id': '',
        'summaries': [],
      }),
      isNull,
    );
    expect(
      service.accept('CONVERSATION_SUMMARY_UPDATE', const {
        'channel_id': 'channel-1',
        'summaries': 'nonsense',
      }),
      isNull,
    );
  });

  test('a summary compares by what it says', () {
    const summary = ConversationSummary(
      id: 's1',
      channelId: 'c',
      topic: 'a',
      summary: 'b',
    );

    expect(
      summary,
      const ConversationSummary(
        id: 's1',
        channelId: 'c',
        topic: 'a',
        summary: 'b',
      ),
    );
    expect(
      summary.hashCode,
      const ConversationSummary(
        id: 's1',
        channelId: 'c',
        topic: 'a',
        summary: 'b',
      ).hashCode,
    );
    expect(
      summary ==
          const ConversationSummary(
            id: 's1',
            channelId: 'c',
            topic: 'a',
            summary: 'different',
          ),
      isFalse,
    );
    expect(summary == Object(), isFalse);
    expect(const ConversationSummary(id: 's', channelId: 'c').isEmpty, isTrue);
  });
}
