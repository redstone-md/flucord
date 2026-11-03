import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import '../../app_log.dart';

final class DiscordVoiceIpDiscovery {
  const DiscordVoiceIpDiscovery({required this.address, required this.port});

  final String address;
  final int port;
}

abstract interface class DiscordVoiceUdpTransport {
  Stream<Uint8List> get packets;

  /// Reports a socket that died after its discovery finished. No more packets
  /// move until the next [discover]. A socket that dies during a discovery
  /// fails that [discover] instead.
  Stream<Object> get socketFailures;

  Future<DiscordVoiceIpDiscovery> discover({
    required String host,
    required int port,
    required int ssrc,
  });

  int send(Uint8List packet);
  Future<void> close();
}

abstract final class DiscordVoiceDiscoveryPacket {
  static const size = 74;

  static Uint8List request(int ssrc) {
    final packet = Uint8List(size);
    final data = ByteData.sublistView(packet);
    data.setUint16(0, 1, Endian.big);
    data.setUint16(2, 70, Endian.big);
    data.setUint32(4, ssrc, Endian.big);
    return packet;
  }

  static DiscordVoiceIpDiscovery? parse(Uint8List packet) {
    if (packet.length < size) return null;
    final data = ByteData.sublistView(packet);
    if (data.getUint16(0, Endian.big) != 2 ||
        data.getUint16(2, Endian.big) != 70) {
      return null;
    }
    var addressEnd = 8;
    while (addressEnd < 72 && packet[addressEnd] != 0) {
      addressEnd++;
    }
    if (addressEnd == 8) return null;
    final address = String.fromCharCodes(packet.sublist(8, addressEnd));
    final port = data.getUint16(72, Endian.big);
    if (port == 0) return null;
    return DiscordVoiceIpDiscovery(address: address, port: port);
  }
}

/// Datagrams a socket would not take yet, let out in order as it frees up.
///
/// `dart:io` keeps a single send in flight per socket on Windows: a send made
/// while one is pending returns 0 and the datagram is gone. A video picture
/// is a burst of packets, so most of each burst was lost before it left the
/// machine, and a viewer's request to send those packets again found nothing
/// to send. Here a datagram the socket refuses waits for the socket's next
/// write event instead.
final class DatagramSendQueue {
  DatagramSendQueue({
    required int Function(Uint8List datagram) send,
    required void Function() awaitWritable,
    this.capacity = defaultCapacity,
  }) : _send = send,
       _awaitWritable = awaitWritable;

  /// About a second of a 1080p share. A socket that has not drained that
  /// much has stopped draining, and a datagram older than that is no use to
  /// anyone.
  static const defaultCapacity = 1024;

  final int capacity;
  final int Function(Uint8List datagram) _send;
  final void Function() _awaitWritable;
  final Queue<Uint8List> _waiting = Queue();

  int get waiting => _waiting.length;

  /// Sends [datagram] now or after the ones already waiting. Answers its
  /// length once the socket has it or it is queued, and 0 when the queue is
  /// full and it was refused.
  int add(Uint8List datagram) {
    if (_waiting.isEmpty) {
      final sent = _send(datagram);
      if (sent > 0) return sent;
    }
    if (_waiting.length >= capacity) return 0;
    _waiting.add(datagram);
    _awaitWritable();
    return datagram.length;
  }

  /// Lets out what waits, oldest first, until the socket refuses again.
  void flush() {
    while (_waiting.isNotEmpty) {
      if (_send(_waiting.first) == 0) {
        _awaitWritable();
        return;
      }
      _waiting.removeFirst();
    }
  }

  void clear() => _waiting.clear();
}

final class IoDiscordVoiceUdpTransport implements DiscordVoiceUdpTransport {
  IoDiscordVoiceUdpTransport({
    Duration discoveryWindow = const Duration(seconds: 5),
    Duration discoveryResend = const Duration(seconds: 1),
  }) : _discoveryWindow = discoveryWindow,
       _discoveryResend = discoveryResend;

  static const _socketClosed = SocketException('Voice UDP socket closed');

  /// How long one discovery may take, and how often it asks again in that
  /// time. A request is a single datagram, and the network may lose it.
  final Duration _discoveryWindow;
  final Duration _discoveryResend;

  final StreamController<Uint8List> _packets = StreamController.broadcast();
  final StreamController<Object> _socketFailures = StreamController.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Completer<DiscordVoiceIpDiscovery>? _discovery;
  DatagramSendQueue? _sendQueue;

  /// Whether the send queue is refusing datagrams, so a full queue is
  /// logged once when it fills rather than once per datagram.
  bool _refusing = false;

  /// Rises with each [discover] and [close]. A discovery reads it after its
  /// waits, to see if a newer call took over the transport in the meantime.
  int _socketClaims = 0;

  @override
  Stream<Uint8List> get packets => _packets.stream;

  @override
  Stream<Object> get socketFailures => _socketFailures.stream;

  @override
  Future<DiscordVoiceIpDiscovery> discover({
    required String host,
    required int port,
    required int ssrc,
  }) async {
    final claim = ++_socketClaims;
    await _closeSocket();
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) throw const SocketException('Voice host not found');
    final address = addresses.first;
    final socket = await RawDatagramSocket.bind(
      address.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    if (claim != _socketClaims) {
      socket.close();
      throw _socketClosed;
    }
    _socket = socket;
    _sendQueue = DatagramSendQueue(
      send: (datagram) => socket.send(datagram, address, port),
      awaitWritable: () => socket.writeEventsEnabled = true,
    );
    _subscription = socket.listen(
      _handleSocketEvent,
      onError: (Object error) => _handleSocketLost(socket, error),
      onDone: () => _handleSocketLost(socket, _socketClosed),
    );
    final pending = Completer<DiscordVoiceIpDiscovery>();
    _discovery = pending;
    final request = DiscordVoiceDiscoveryPacket.request(ssrc);
    socket.send(request, address, port);
    final resend = Timer.periodic(
      _discoveryResend,
      (_) => socket.send(request, address, port),
    );
    try {
      return await pending.future.timeout(_discoveryWindow);
    } finally {
      resend.cancel();
      if (identical(_discovery, pending)) _discovery = null;
    }
  }

  /// `dart:io` closes a datagram socket after any failed send. It reports that
  /// once as an error and then as the end of the stream, and every later send
  /// on it returns 0 with no error. Measured on Linux with "message too long"
  /// and "permission denied". Other systems and errors are not measured.
  void _handleSocketLost(RawDatagramSocket socket, Object error) {
    if (!identical(socket, _socket)) return;
    // A running discovery reports the loss to its own caller.
    final discovering = _discovery != null;
    unawaited(_closeSocket(error));
    if (!discovering && !_socketFailures.isClosed) _socketFailures.add(error);
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.write) _sendQueue?.flush();
    if (event != RawSocketEvent.read) return;
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      // `dart:io` gives each datagram bytes of its own, so no copy is needed.
      final packet = datagram!.data;
      final pending = _discovery;
      if (pending != null && !pending.isCompleted) {
        final result = DiscordVoiceDiscoveryPacket.parse(packet);
        if (result != null) {
          pending.complete(result);
          _discovery = null;
          continue;
        }
      }
      if (!_packets.isClosed) _packets.add(packet);
    }
  }

  /// Answers the bytes taken: sent now, or queued behind a send still in
  /// flight. 0 when there is no socket, or the queue is full.
  @override
  int send(Uint8List packet) {
    final queue = _sendQueue;
    if (queue == null) return 0;
    final taken = queue.add(packet);
    if (taken == 0 && !_refusing) {
      AppLog.warning(
        'voice.transport',
        'udp send queue full at ${queue.waiting}: datagrams are dropped '
            'until the socket drains',
      );
    }
    _refusing = taken == 0;
    return taken;
  }

  Future<void> _closeSocket([Object reason = _socketClosed]) async {
    final socket = _socket;
    final subscription = _subscription;
    final pending = _discovery;
    _socket = null;
    _subscription = null;
    _sendQueue?.clear();
    _sendQueue = null;
    _refusing = false;
    _discovery = null;
    if (pending != null && !pending.isCompleted) pending.completeError(reason);
    await subscription?.cancel();
    socket?.close();
  }

  @override
  Future<void> close() async {
    _socketClaims++;
    await _closeSocket();
    await _packets.close();
    await _socketFailures.close();
  }
}
