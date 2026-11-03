import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_voice_udp_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// A socket the way `dart:io` runs one on Windows: one send in flight, and
/// a send made while it is refuses with 0.
final class _OneInFlightSocket {
  final List<int> wire = [];
  bool _pending = false;
  int writeWaits = 0;

  int send(Uint8List datagram) {
    if (_pending) return 0;
    _pending = true;
    wire.add(datagram.first);
    return datagram.length;
  }

  void completeSend() => _pending = false;
}

Uint8List _datagram(int tag) => Uint8List.fromList([tag, 0, 0, 0]);

void main() {
  test('a burst sent while one send is in flight goes out whole and in '
      'order', () {
    final socket = _OneInFlightSocket();
    final queue = DatagramSendQueue(
      send: socket.send,
      awaitWritable: () => socket.writeWaits++,
    );

    final taken = [
      for (var tag = 1; tag <= 5; tag++) queue.add(_datagram(tag)),
    ];

    expect(taken, everyElement(4));
    expect(socket.wire, [1]);
    expect(socket.writeWaits, greaterThan(0));
    for (var event = 0; event < 4; event++) {
      socket.completeSend();
      queue.flush();
    }
    expect(socket.wire, [1, 2, 3, 4, 5]);
    expect(queue.waiting, 0);
  });

  test('a full queue refuses with 0 rather than taking what it cannot '
      'send', () {
    final socket = _OneInFlightSocket();
    final queue = DatagramSendQueue(
      send: socket.send,
      awaitWritable: () {},
      capacity: 2,
    );

    queue
      ..add(_datagram(1))
      ..add(_datagram(2))
      ..add(_datagram(3));

    expect(queue.add(_datagram(4)), 0);
    socket.completeSend();
    queue.flush();
    expect(socket.wire, [1, 2]);
  });
}
