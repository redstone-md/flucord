// Counts what the video receive path allocates per packet, class by class.
//
// Real datagrams go over loopback into the real transport, cipher, reorder
// buffer and picture receiver. Only the group decryption is modelled: libdave is
// not loaded, so the picture goes in and out of native memory through the same
// buffers `NativeDaveDecryptor` uses.
//
// The VM's allocation profile only counts objects that still exist. A new space
// too large to fill means nothing is collected while this runs, so the growth
// from start to end is everything allocated. The script refuses to report if a
// collection happened after all.
//
// Run from the repo root, after `flutter pub get`:
//
//   dart --new_gen_semi_initial_size=4000 --new_gen_semi_max_size=4000 tool/receive_path_allocations.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flucord/src/data/dave/native_dave_buffers.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_rtp_reorder_buffer.dart';
import 'package:flucord/src/data/discord/discord_video_picture_receiver.dart';
import 'package:flucord/src/data/discord/discord_video_rtp_sender.dart';
import 'package:flucord/src/data/discord/discord_voice_transport_cipher.dart';
import 'package:flucord/src/data/discord/discord_voice_udp_transport.dart';
import 'package:flucord/src/domain/video_encoder.dart';

const _ssrc = 92;

/// A picture of a 3 Mbit/s stream at 30 pictures a second, about 11 packets. A
/// larger one makes the old path's lists big enough to live in old space, whose
/// collector cannot be held off, and the count would come out wrong.
const _pictureBytes = 12500;
const _warmUpPictures = 100;
const _measuredPictures = 100;

/// Classes under this many bytes per packet are summed into one line.
const _reportFloor = 16.0;

Future<void> main() async {
  final secretKey = List<int>.generate(32, (index) => index);
  final pictures = _encryptedPictures(secretKey);

  final server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = server.receive();
    if (datagram != null) _answerDiscovery(server, datagram);
  });
  final transport = IoDiscordVoiceUdpTransport();
  final client = await transport.discover(
    host: InternetAddress.loopbackIPv4.address,
    port: server.port,
    ssrc: _ssrc,
  );
  final clientPort = client.port;

  var whole = 0;
  var delivered = Completer<void>();
  final chain = _ReceiveChain(secretKey);
  transport.packets.listen((packet) {
    if (chain.accept(packet)) {
      whole++;
      delivered.complete();
    }
  });

  Future<int> send(int count) async {
    var sent = 0;
    for (var index = 0; index < count; index++) {
      delivered = Completer<void>();
      final picture = pictures.removeLast();
      for (final packet in picture) {
        server.send(packet, InternetAddress.loopbackIPv4, clientPort);
      }
      sent += picture.length;
      await delivered.future.timeout(const Duration(seconds: 5));
    }
    return sent;
  }

  await send(_warmUpPictures);

  final vm = await _VmService.connect();
  final first = await vm.allocations();
  final start = await vm.allocations();
  whole = 0;
  final packets = await send(_measuredPictures);
  final end = await vm.allocations();
  await vm.close();

  if (whole != _measuredPictures) {
    throw StateError('$whole of $_measuredPictures pictures came through');
  }
  if (end.collections != first.collections) {
    throw StateError('A collection ran: the new space flags are missing.');
  }
  _report(start.minus(first), end.minus(start), packets);

  await transport.close();
  server.close();
}

/// The receive path after the socket, in the order the app runs it.
final class _ReceiveChain {
  _ReceiveChain(List<int> secretKey)
    : _cipher = DiscordVoiceTransportCipher(
        mode: DiscordVoiceTransportMode.aes256GcmRtpSize,
        secretKey: secretKey,
      );

  final DiscordVoiceTransportCipher _cipher;

  /// The hold time only matters for a hole, and loopback leaves none.
  final _reorder = DiscordRtpReorderBuffer(
    holdTime: () => const Duration(milliseconds: 100),
  );
  final _pictures = DiscordVideoPictureReceiver(
    decryptor: _throughNativeMemory,
  );

  /// Answers whether this packet finished a picture.
  bool accept(Uint8List packet) {
    var finished = false;
    for (final ordered in _reorder.add(_cipher.decryptPacket(packet))) {
      final frame = ordered.frame;
      final picture = _pictures.accept(
        Uint8List.fromList(frame.payload),
        marker: frame.header.marker,
        rtpTimestamp: frame.header.timestamp,
      );
      if (picture != null) finished = true;
    }
    return finished;
  }
}

/// What group decryption costs around the native call itself.
Uint8List _throughNativeMemory(Uint8List picture) => using((arena) {
  final input = NativeDaveBuffers.allocate(arena, picture);
  return Uint8List.fromList(NativeDaveBuffers.copy(input, picture.length));
});

List<List<Uint8List>> _encryptedPictures(List<int> secretKey) {
  final cipher = DiscordVoiceTransportCipher(
    mode: DiscordVoiceTransportMode.aes256GcmRtpSize,
    secretKey: secretKey,
  );
  final sender = DiscordVideoRtpSender(ssrc: _ssrc);
  final pictures = <List<Uint8List>>[];
  for (var index = 0; index < _warmUpPictures + _measuredPictures; index++) {
    final accessUnit = Uint8List(_pictureBytes)
      ..[3] = 1
      ..[4] = 0x41
      ..fillRange(5, _pictureBytes, 0x55);
    final frame = EncodedVideoFrame(
      bytes: accessUnit,
      timestamp: Duration(milliseconds: index * 33),
      isKeyframe: false,
    );
    pictures.add([
      for (final packet in sender.packetsFor(frame))
        cipher.encryptFrame(
          DiscordRtpFrame(
            header: DiscordRtpHeader(
              sequence: packet.sequence,
              timestamp: packet.timestamp,
              ssrc: _ssrc,
              payloadType: DiscordRtpHeader.discordVideoPayloadType,
              marker: packet.marker,
            ),
            payload: packet.payload,
          ),
        ),
    ]);
  }
  return pictures.reversed.toList();
}

void _answerDiscovery(RawDatagramSocket server, Datagram datagram) {
  final answer = Uint8List(DiscordVoiceDiscoveryPacket.size);
  final data = ByteData.sublistView(answer);
  data.setUint16(0, 2);
  data.setUint16(2, 70);
  answer.setRange(8, 17, ascii.encode('127.0.0.1'));
  data.setUint16(72, datagram.port);
  server.send(answer, datagram.address, datagram.port);
}

/// [snapshotCost] is what reading the profile allocated by itself: reading the
/// last profile falls inside [measured], so it is taken back out.
void _report(_Allocations snapshotCost, _Allocations measured, int packets) {
  final grown = <(String, int, int)>[];
  for (final (name, bytes, count) in measured.minus(snapshotCost).rows) {
    if (bytes > 0) grown.add((name, bytes, count));
  }
  grown.sort((a, b) => b.$2.compareTo(a.$2));

  final total = grown.fold<int>(0, (sum, row) => sum + row.$2);
  final objects = grown.fold<int>(0, (sum, row) => sum + row.$3);
  stdout.writeln('$packets packets, $_measuredPictures pictures');
  stdout.writeln('bytes/packet  objects/packet  class');
  var rest = 0.0;
  for (final (name, bytes, count) in grown) {
    final perPacket = bytes / packets;
    if (perPacket < _reportFloor) {
      rest += perPacket;
      continue;
    }
    stdout.writeln(
      '${perPacket.toStringAsFixed(0).padLeft(12)}  '
      '${(count / packets).toStringAsFixed(1).padLeft(14)}  $name',
    );
  }
  stdout.writeln(
    '${rest.toStringAsFixed(0).padLeft(12)}  ${' ' * 14}  everything else',
  );
  stdout.writeln(
    '${(total / packets).toStringAsFixed(0).padLeft(12)}  '
    '${(objects / packets).toStringAsFixed(1).padLeft(14)}  total',
  );
}

/// Bytes and instances per class, as the heap holds them right now.
final class _Allocations {
  const _Allocations(this.classes, this.collections);

  final Map<String, (int, int)> classes;
  final int collections;

  Iterable<(String, int, int)> get rows => classes.entries.map(
    (entry) => (entry.key, entry.value.$1, entry.value.$2),
  );

  _Allocations minus(_Allocations other) => _Allocations({
    for (final MapEntry(key: name, value: mine) in classes.entries)
      name: (
        mine.$1 - (other.classes[name]?.$1 ?? 0),
        mine.$2 - (other.classes[name]?.$2 ?? 0),
      ),
  }, collections);
}

/// The little of the VM service protocol this needs, over its websocket.
final class _VmService {
  _VmService._(this._socket, this._replies, this._isolateId);

  static Future<_VmService> connect() async {
    final info = await Service.controlWebServer(
      enable: true,
      silenceOutput: true,
    );
    final socket = await WebSocket.connect('${info.serverWebSocketUri}');
    return _VmService._(
      socket,
      socket
          .map((message) => jsonDecode(message as String))
          .asBroadcastStream(),
      Service.getIsolateId(Isolate.current)!,
    );
  }

  final WebSocket _socket;
  final Stream<Object?> _replies;
  final String _isolateId;
  var _nextId = 0;

  Future<_Allocations> allocations() async {
    final profile = await _call('getAllocationProfile', {
      'isolateId': _isolateId,
    });
    final isolate = await _call('getIsolate', {'isolateId': _isolateId});
    return _Allocations(
      {
        for (final member in profile['members'] as List<Object?>)
          if (member case {
            'class': {'name': final String name},
            'bytesCurrent': final int bytes,
            'instancesCurrent': final int instances,
          })
            name: (bytes, instances),
      },
      switch (isolate['_heaps']) {
        {
          'new': {'collections': final int young},
          'old': {'collections': final int old},
        } =>
          young + old,
        _ => throw StateError('This VM reports no collection counts.'),
      },
    );
  }

  Future<Map<String, Object?>> _call(
    String method,
    Map<String, Object?> params,
  ) async {
    final id = '${_nextId++}';
    final reply = _replies.firstWhere(
      (message) => message is Map && message['id'] == id,
    );
    _socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    final message = await reply as Map<String, Object?>;
    return message['result']! as Map<String, Object?>;
  }

  Future<void> close() async {
    await _socket.close();
    await Service.controlWebServer(enable: false);
  }
}
