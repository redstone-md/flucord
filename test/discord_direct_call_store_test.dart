import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_direct_call_store.dart';
import 'package:flucord/src/domain/voice_call.dart';

void main() {
  test('reads every documented CALL_CREATE field', () {
    final store = DiscordDirectCallStore();

    final events = store.accept(
      eventName: 'CALL_CREATE',
      data: const {
        'channel_id': 'dm-1',
        'message_id': 'call-message',
        'region': 'rotterdam',
        'ongoing_rings': {'me': 'caller-1'},
      },
    );

    final call = (events.single as DirectCallUpdatedEvent).call;
    expect(call.channelId, 'dm-1');
    expect(call.messageId, 'call-message');
    expect(call.region, 'rotterdam');
    expect(call.unavailable, isFalse);
    expect(call.isRingable, isTrue);
    expect(call.ringing, ['me']);
    // R08: the map is keyed by the recipient and valued with the caller.
    expect(call.callerFor('me'), 'caller-1');
    expect(call.callerFor('caller-1'), isNull);
    expect(store.call('dm-1'), same(call));
  });

  test('an update carrying nothing new reports no change', () {
    final store = DiscordDirectCallStore();
    const data = {
      'channel_id': 'dm-1',
      'message_id': 'call-message',
      'region': 'rotterdam',
      'ongoing_rings': {'me': 'caller-1'},
    };

    expect(store.accept(eventName: 'CALL_CREATE', data: data), hasLength(1));
    expect(store.accept(eventName: 'CALL_UPDATE', data: data), isEmpty);
    expect(
      store.accept(
        eventName: 'CALL_UPDATE',
        data: const {
          'channel_id': 'dm-1',
          'message_id': 'call-message',
          'region': 'rotterdam',
          'ongoing_rings': <String, Object?>{},
        },
      ),
      hasLength(1),
    );
    expect(store.call('dm-1')!.ringing, isEmpty);
  });

  test('a ring for a different person is still a change', () {
    final store = DiscordDirectCallStore()
      ..accept(
        eventName: 'CALL_CREATE',
        data: const {
          'channel_id': 'dm-1',
          'ongoing_rings': {'me': 'caller-1'},
        },
      );

    final events = store.accept(
      eventName: 'CALL_UPDATE',
      data: const {
        'channel_id': 'dm-1',
        'ongoing_rings': {'me': 'caller-2'},
      },
    );

    expect(
      (events.single as DirectCallUpdatedEvent).call.callerFor('me'),
      'caller-2',
    );
  });

  test('a call with no message id cannot be rung yet', () {
    final store = DiscordDirectCallStore()
      ..accept(eventName: 'CALL_CREATE', data: const {'channel_id': 'dm-1'});

    final call = store.call('dm-1')!;
    expect(call.messageId, isNull);
    expect(call.region, isNull);
    expect(call.isRingable, isFalse);
  });

  test('an unavailable delete flags the call instead of dropping it', () {
    final store = DiscordDirectCallStore()
      ..accept(
        eventName: 'CALL_CREATE',
        data: const {'channel_id': 'dm-1', 'message_id': 'call-message'},
      );

    final events = store.accept(
      eventName: 'CALL_DELETE',
      data: const {'channel_id': 'dm-1', 'unavailable': true},
    );

    final call = (events.single as DirectCallUpdatedEvent).call;
    expect(call.unavailable, isTrue);
    expect(call.messageId, 'call-message');
    expect(call.isRingable, isFalse, reason: 'a ring would be rejected');
    // Flagging twice is not a second change.
    expect(
      store.accept(
        eventName: 'CALL_DELETE',
        data: const {'channel_id': 'dm-1', 'unavailable': true},
      ),
      isEmpty,
    );
  });

  test('a plain delete ends the call once', () {
    final store = DiscordDirectCallStore()
      ..accept(eventName: 'CALL_CREATE', data: const {'channel_id': 'dm-1'});

    final events = store.accept(
      eventName: 'CALL_DELETE',
      data: const {'channel_id': 'dm-1'},
    );

    expect((events.single as DirectCallEndedEvent).channelId, 'dm-1');
    expect(store.call('dm-1'), isNull);
    expect(
      store.accept(
        eventName: 'CALL_DELETE',
        data: const {'channel_id': 'dm-1'},
      ),
      isEmpty,
    );
  });

  test('an unavailable delete for a call nobody knows about is ignored', () {
    final store = DiscordDirectCallStore();

    expect(
      store.accept(
        eventName: 'CALL_DELETE',
        data: const {'channel_id': 'dm-1', 'unavailable': true},
      ),
      isEmpty,
    );
  });

  test('names whoever is ringing the local user', () {
    final store = DiscordDirectCallStore()
      ..accept(
        eventName: 'CALL_CREATE',
        data: const {
          'channel_id': 'dm-1',
          'message_id': 'call-message',
          'ongoing_rings': {'me': 'caller-1'},
        },
      );

    expect(
      store.incomingCallFor('me'),
      const IncomingCall(channelId: 'dm-1', callerId: 'caller-1'),
    );
    expect(store.incomingCallFor('somebody-else'), isNull);
  });

  test('an unavailable call never rings', () {
    final store = DiscordDirectCallStore()
      ..accept(
        eventName: 'CALL_CREATE',
        data: const {
          'channel_id': 'dm-1',
          'ongoing_rings': {'me': 'caller-1'},
        },
      )
      ..accept(
        eventName: 'CALL_DELETE',
        data: const {'channel_id': 'dm-1', 'unavailable': true},
      );

    expect(store.incomingCallFor('me'), isNull);
  });

  test('a replayed READY drops every subscription-backed record', () {
    final store = DiscordDirectCallStore()
      ..accept(eventName: 'CALL_CREATE', data: const {'channel_id': 'dm-1'})
      ..accept(eventName: 'CALL_CREATE', data: const {'channel_id': 'dm-2'});

    final events = store.accept(
      eventName: 'READY',
      data: const {'user': <String, Object?>{}},
    );

    expect(events.map((event) => (event as DirectCallEndedEvent).channelId), [
      'dm-1',
      'dm-2',
    ]);
    expect(store.call('dm-1'), isNull);
    expect(store.call('dm-2'), isNull);
    expect(
      store.accept(
        eventName: 'READY',
        data: const {'user': <String, Object?>{}},
      ),
      isEmpty,
    );
  });

  test('drops records and rings it cannot read', () {
    final store = DiscordDirectCallStore();

    expect(
      store.accept(eventName: 'MESSAGE_CREATE', data: const {'id': 'm-1'}),
      isEmpty,
    );
    expect(store.accept(eventName: 'CALL_CREATE', data: const {}), isEmpty);
    expect(
      store.accept(eventName: 'CALL_CREATE', data: const {'channel_id': ''}),
      isEmpty,
    );
    expect(
      store.accept(eventName: 'CALL_DELETE', data: const {'channel_id': 7}),
      isEmpty,
    );

    store.accept(
      eventName: 'CALL_CREATE',
      data: const {
        'channel_id': 'dm-1',
        'message_id': 7,
        'region': '',
        // Nulls, empties and non-strings are stale entries, not rings.
        'ongoing_rings': {'me': null, '': 'caller-1', 'other': '', 7: 'x'},
      },
    );
    expect(store.call('dm-1')!.messageId, isNull);
    expect(store.call('dm-1')!.region, isNull);
    expect(store.call('dm-1')!.ringing, isEmpty);

    store.accept(
      eventName: 'CALL_UPDATE',
      data: const {'channel_id': 'dm-1', 'ongoing_rings': 'not-a-map'},
    );
    expect(store.call('dm-1')!.ringing, isEmpty);
  });

  test('bounds a ring map that arrived off the wire', () {
    final store = DiscordDirectCallStore(maxRings: 2);

    store.accept(
      eventName: 'CALL_CREATE',
      data: const {
        'channel_id': 'dm-1',
        'ongoing_rings': {'a': 'x', 'b': 'x', 'c': 'x', 'd': 'x'},
      },
    );

    expect(store.call('dm-1')!.ringing, ['a', 'b']);
  });

  test('clear forgets everything', () {
    final store = DiscordDirectCallStore()
      ..accept(eventName: 'CALL_CREATE', data: const {'channel_id': 'dm-1'})
      ..clear();

    expect(store.call('dm-1'), isNull);
  });

  test('flagging a call unavailable keeps every other field', () {
    const call = DirectCall(
      channelId: 'dm-1',
      messageId: 'call-message',
      region: 'rotterdam',
      ongoingRings: {'me': 'caller-1'},
    );

    final copy = call.markUnavailable();
    expect(copy.channelId, 'dm-1');
    expect(copy.messageId, 'call-message');
    expect(copy.region, 'rotterdam');
    expect(copy.ongoingRings, {'me': 'caller-1'});
    expect(copy.unavailable, isTrue);

    const other = IncomingCall(channelId: 'dm-1', callerId: 'caller-1');
    expect(
      other,
      isNot(const IncomingCall(channelId: 'dm-2', callerId: 'caller-1')),
    );
    expect(
      other.hashCode,
      const IncomingCall(channelId: 'dm-1', callerId: 'caller-1').hashCode,
    );
  });
}
