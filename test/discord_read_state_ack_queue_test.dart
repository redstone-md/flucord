import 'dart:async';

import 'package:flucord/src/data/discord/discord_desktop_rest_protocol.dart';
import 'package:flucord/src/data/discord/discord_read_state_ack_queue.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _channelId = '222222222222222222';
const _olderMessage = '123456789012345678';
const _newerMessage = '234567890123456789';

void main() {
  test('coalesces acks inside the debounce window', () async {
    final transport = _RecordingTransport();
    final queue = _queue(transport, debounce: const Duration(milliseconds: 30));
    addTearDown(queue.close);

    queue
      ..schedule(
        const DiscordPendingAck(
          channelId: _channelId,
          messageId: _olderMessage,
        ),
      )
      ..schedule(
        const DiscordPendingAck(
          channelId: _channelId,
          messageId: _newerMessage,
          lastViewed: 2400,
          flags: 1,
        ),
      );

    expect(transport.requests, isEmpty);
    await _settle(const Duration(milliseconds: 80));

    expect(transport.requests, hasLength(1));
    final request = transport.requests.single;
    expect(request.path, '/channels/$_channelId/messages/$_newerMessage/ack');
    expect(request.body, {'token': null, 'last_viewed': 2400, 'flags': 1});
    expect(queue.hasPendingWork, isFalse);
  });

  test('an immediate ack skips the timer that is already running', () async {
    final transport = _RecordingTransport();
    final queue = _queue(transport, debounce: const Duration(seconds: 30));
    addTearDown(queue.close);

    queue
      ..schedule(
        const DiscordPendingAck(
          channelId: _channelId,
          messageId: _olderMessage,
        ),
      )
      ..schedule(
        const DiscordPendingAck(
          channelId: _channelId,
          messageId: _newerMessage,
        ),
        immediate: true,
      );
    await _settle();

    expect(transport.requests, hasLength(1));
    expect(
      transport.requests.single.path,
      '/channels/$_channelId/messages/$_newerMessage/ack',
    );
  });

  test('rolls the ack token forward from each response', () async {
    final transport = _RecordingTransport(
      responses: [
        {'token': 'first'},
        {'token': 'second'},
      ],
    );
    final queue = _queue(transport);
    addTearDown(queue.close);

    queue.schedule(
      const DiscordPendingAck(channelId: _channelId, messageId: _olderMessage),
      immediate: true,
    );
    await _settle();
    expect(queue.token, 'first');
    expect(transport.requests.single.body!['token'], isNull);

    queue.schedule(
      const DiscordPendingAck(channelId: _channelId, messageId: _newerMessage),
      immediate: true,
    );
    await _settle();
    expect(queue.token, 'second');
    expect(transport.requests.last.body!['token'], 'first');
  });

  test('refuses a token that belongs to a session we have left', () async {
    final gate = Completer<void>();
    final transport = _RecordingTransport(
      responses: [
        {'token': 'stale'},
      ],
      gate: gate,
    );
    final queue = _queue(transport);
    addTearDown(queue.close);

    queue.bindSession('user-a');
    queue.schedule(
      const DiscordPendingAck(channelId: _channelId, messageId: _olderMessage),
      immediate: true,
    );
    await _settle();
    queue.bindSession('user-b');
    gate.complete();
    await _settle();

    expect(queue.token, isNull);
  });

  test('binding a session drops the token and everything pending', () async {
    final transport = _RecordingTransport();
    final queue = _queue(transport, debounce: const Duration(seconds: 30));
    addTearDown(queue.close);

    queue
      ..schedule(
        const DiscordPendingAck(
          channelId: _channelId,
          messageId: _olderMessage,
        ),
      )
      ..enqueueBulk([_bulkEntry()])
      ..bindSession('user-a');
    await queue.flush();

    expect(transport.requests, isEmpty);
    expect(queue.hasPendingWork, isFalse);
  });

  test('cancel drops one channel and flush sends the rest', () async {
    final transport = _RecordingTransport();
    final queue = _queue(transport, debounce: const Duration(seconds: 30));
    addTearDown(queue.close);

    queue
      ..schedule(
        const DiscordPendingAck(
          channelId: _channelId,
          messageId: _olderMessage,
        ),
      )
      ..cancel(_channelId);
    await queue.flush();
    expect(transport.requests, isEmpty);

    queue.schedule(
      const DiscordPendingAck(channelId: _channelId, messageId: _newerMessage),
    );
    await queue.flush();
    expect(transport.requests, hasLength(1));
  });

  test('retries a server failure and gives up after three attempts', () async {
    final delays = <Duration>[];
    final transport = _RecordingTransport(failures: 2, failureStatus: 500);
    final queue = _queue(transport, delays: delays);
    addTearDown(queue.close);

    await queue.sendNow(DiscordDesktopReadStateRequests.ackPins(_channelId));
    expect(transport.requests, hasLength(3));
    expect(delays, [
      DiscordReadStateAckQueue.retryStep,
      DiscordReadStateAckQueue.retryStep * 2,
    ]);

    final hopeless = _RecordingTransport(failures: 9, failureStatus: 503);
    final second = _queue(hopeless);
    addTearDown(second.close);
    await expectLater(
      second.sendNow(DiscordDesktopReadStateRequests.ackPins(_channelId)),
      throwsA(isA<DiscordApiException>()),
    );
    expect(hopeless.requests, hasLength(3));
  });

  test('abandons a retry when the account changes underneath it', () async {
    final transport = _RecordingTransport(failures: 9, failureStatus: 500);
    late final DiscordReadStateAckQueue queue;
    queue = DiscordReadStateAckQueue(
      send: transport.send,
      debounce: Duration.zero,
      delay: (_) async => queue.bindSession('user-b'),
    );
    addTearDown(queue.close);
    queue.bindSession('user-a');

    await expectLater(
      queue.sendNow(DiscordDesktopReadStateRequests.ackPins(_channelId)),
      throwsA(isA<StateError>()),
    );
    expect(transport.requests, hasLength(1));
  });

  test('does not retry a rejection the server will repeat', () async {
    final transport = _RecordingTransport(failures: 9, failureStatus: 403);
    final queue = _queue(transport);
    addTearDown(queue.close);

    await expectLater(
      queue.sendNow(DiscordDesktopReadStateRequests.ackPins(_channelId)),
      throwsA(isA<DiscordApiException>()),
    );
    expect(transport.requests, hasLength(1));
  });

  test('retries a rate limit and a transport-level failure', () async {
    final rateLimited = _RecordingTransport(failures: 1, failureStatus: 429);
    final queue = _queue(rateLimited);
    addTearDown(queue.close);
    await queue.sendNow(DiscordDesktopReadStateRequests.ackPins(_channelId));
    expect(rateLimited.requests, hasLength(2));

    final broken = _RecordingTransport(failures: 1, failureStatus: null);
    final second = _queue(broken);
    addTearDown(second.close);
    await second.sendNow(DiscordDesktopReadStateRequests.ackPins(_channelId));
    expect(broken.requests, hasLength(2));
  });

  test('pumps the bulk queue in hundreds with a pause between', () async {
    final delays = <Duration>[];
    final transport = _RecordingTransport();
    final queue = _queue(transport, delays: delays);
    addTearDown(queue.close);

    queue.enqueueBulk([for (var index = 0; index < 150; index++) _bulkEntry()]);
    await queue.flush();

    expect(transport.requests, hasLength(2));
    expect(
      (transport.requests.first.body!['read_states']! as List),
      hasLength(100),
    );
    expect(
      (transport.requests.last.body!['read_states']! as List),
      hasLength(50),
    );
    expect(delays, [DiscordReadStateAckQueue.bulkBatchSpacing]);
  });

  test('a failed batch clears the whole queue', () async {
    final transport = _RecordingTransport(failures: 9, failureStatus: 500);
    final queue = _queue(transport);
    addTearDown(queue.close);

    queue.enqueueBulk([for (var index = 0; index < 150; index++) _bulkEntry()]);
    await queue.flush();

    expect(transport.requests, hasLength(3));
    expect(queue.hasPendingWork, isFalse);
  });

  test('a closed queue accepts nothing more', () async {
    final transport = _RecordingTransport();
    final queue = _queue(transport, debounce: const Duration(seconds: 30));

    queue.schedule(
      const DiscordPendingAck(channelId: _channelId, messageId: _olderMessage),
    );
    await queue.close();
    queue
      ..schedule(
        const DiscordPendingAck(
          channelId: _channelId,
          messageId: _newerMessage,
        ),
        immediate: true,
      )
      ..enqueueBulk([_bulkEntry()]);
    await _settle();

    expect(transport.requests, isEmpty);
    expect(queue.hasPendingWork, isFalse);
  });
}

Map<String, Object?> _bulkEntry() => {
  'channel_id': _channelId,
  'message_id': _newerMessage,
  'read_state_type': 0,
};

DiscordReadStateAckQueue _queue(
  _RecordingTransport transport, {
  Duration debounce = Duration.zero,
  List<Duration>? delays,
}) => DiscordReadStateAckQueue(
  send: transport.send,
  debounce: debounce,
  delay: (duration) async => delays?.add(duration),
);

Future<void> _settle([Duration duration = const Duration(milliseconds: 20)]) =>
    Future<void>.delayed(duration);

final class _RecordingTransport {
  _RecordingTransport({
    List<Map<String, Object?>?> responses = const [],
    this.failures = 0,
    this.failureStatus = 500,
    this.gate,
  }) : _responses = [...responses];

  final List<Map<String, Object?>?> _responses;
  final int failures;
  final int? failureStatus;
  final Completer<void>? gate;
  final List<DiscordDesktopRestRequest> requests = [];

  Future<Map<String, Object?>?> send(DiscordDesktopRestRequest request) async {
    requests.add(request);
    if (requests.length <= failures) {
      final status = failureStatus;
      if (status == null) throw StateError('socket closed');
      throw DiscordApiException(statusCode: status, message: 'nope');
    }
    if (gate != null) await gate!.future;
    return _responses.isEmpty ? null : _responses.removeAt(0);
  }
}
