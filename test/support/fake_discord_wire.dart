/// The two fakes under the desktop repository: everything above them is real.
///
/// A test feeds the gateway what Discord would send, and reads back the frames
/// and requests the client sent. `SessionHarness` runs the whole app on these;
/// a repository test can also use them directly.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';
import 'package:flucord/src/data/discord/discord_etf_codec.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';

/// One gateway connection, in the encoding the client asked for when it dialled.
final class MemoryDesktopWebSocket implements DiscordDesktopWebSocket {
  MemoryDesktopWebSocket._({required bool etf}) : _etf = etf;

  /// A socket that speaks ETF, made before the dial so a test can fill it
  /// first. Hand it to [MemoryDesktopWebSocketConnector.answering].
  MemoryDesktopWebSocket.etf() : this._(etf: true);

  final bool _etf;
  final StreamController<Object?> _messages = StreamController();
  final List<Object> _sent = [];
  bool _open = true;
  bool _closeHeld = false;
  int? _closeCode;

  /// Every frame the client sent on this socket, decoded, oldest first.
  List<Map<String, Object?>> get frames => [
    for (final frame in _sent)
      (frame is Uint8List
              ? DiscordEtfCodec.decode(frame)
              : jsonDecode('$frame'))
          as Map<String, Object?>,
  ];

  /// Delivers one gateway payload to the client.
  void receive(Map<String, Object?> payload) => _messages.add(
    _etf ? DiscordEtfCodec.encode(payload) : jsonEncode(payload),
  );

  /// Delivers [frame] as the socket hands it over, with no encoding. For a frame
  /// that is broken, or one the test has already encoded.
  void receiveRaw(Object? frame) => _messages.add(frame);

  /// Closes from the server's side, as a dropped connection does.
  Future<void> dropConnection({int? code}) {
    _closeCode = code;
    return _finishClose();
  }

  /// Makes a close from the client slow, as a real close handshake is: the
  /// socket stops being open at once, frames can still arrive, and the done
  /// event waits for [completeClose].
  void holdClose() => _closeHeld = true;

  /// The server answers the close, so the done event of a held close arrives.
  Future<void> completeClose() => _finishClose();

  /// The connection fails with [error], which ends the client's subscription.
  void failConnection(Object error) => _messages.addError(error);

  @override
  int? get closeCode => _closeCode;

  @override
  bool get isOpen => _open;

  @override
  Stream<Object?> get messages => _messages.stream;

  /// While set, a write throws this, as a socket that closed mid-frame does.
  Object? sendFailure;

  @override
  void send(String data) {
    _throwIfFailing();
    _sent.add(data);
  }

  @override
  void sendBinary(List<int> data) {
    _throwIfFailing();
    _sent.add(Uint8List.fromList(data));
  }

  void _throwIfFailing() {
    if (sendFailure case final failure?) throw failure;
  }

  @override
  Future<void> close() async {
    if (_closeHeld) {
      _open = false;
      return;
    }
    await _finishClose();
  }

  Future<void> _finishClose() async {
    _open = false;
    if (!_messages.isClosed) await _messages.close();
  }
}

/// Answers each dial with a new socket, and keeps them all in order.
final class MemoryDesktopWebSocketConnector
    implements DiscordDesktopWebSocketConnector {
  MemoryDesktopWebSocketConnector() : _prepared = null;

  /// Answers every dial with [socket], which the test made and may have filled
  /// before the client connected.
  MemoryDesktopWebSocketConnector.answering(MemoryDesktopWebSocket socket)
    : _prepared = socket;

  final MemoryDesktopWebSocket? _prepared;
  final List<MemoryDesktopWebSocket> sockets = [];

  /// Every dial the client started, including one still held open.
  int dials = 0;

  Completer<void>? _heldDials;

  /// Keeps each later dial in flight until [releaseDials]. Its socket joins
  /// [sockets] when the dial returns.
  void holdDials() => _heldDials ??= Completer();

  void releaseDials() {
    _heldDials?.complete();
    _heldDials = null;
  }

  @override
  Future<DiscordDesktopWebSocket> connect(Uri uri) async {
    dials++;
    await _heldDials?.future;
    final socket =
        _prepared ??
        MemoryDesktopWebSocket._(etf: uri.queryParameters['encoding'] == 'etf');
    sockets.add(socket);
    return socket;
  }
}

/// One HTTP request as the client sent it.
final class RecordedRequest {
  const RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int>? body;

  /// The body decoded as JSON. Null when the request had no body.
  Object? get json => body == null ? null : jsonDecode(utf8.decode(body!));
}

/// Answers a request. May return a future the test completes later, which is
/// how a test holds a request open.
typedef FakeRoute =
    FutureOr<DiscordHttpResponse> Function(RecordedRequest request);

/// The HTTP side: records every request and answers from routes.
///
/// A request with no route goes to [fallback], which answers 404 unless a test
/// says otherwise. The gateway lookup is routed from the start.
final class FakeDiscordTransport implements DiscordHttpTransport {
  FakeDiscordTransport({this.fallback = notFound}) {
    on(
      'GET',
      '/api/v9/gateway',
      (_) => jsonResponse({'url': 'wss://gateway.discord.gg'}),
    );
  }

  final FakeRoute fallback;

  /// Every request the client made, oldest first.
  final List<RecordedRequest> requests = [];

  final Map<String, FakeRoute> _routes = {};

  /// Answers [method] on [path] with [route]. A later call replaces an earlier
  /// one. [path] is the full path, such as `/api/v9/channels/1/messages`, with
  /// no query string.
  void on(String method, String path, FakeRoute route) =>
      _routes['$method $path'] = route;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    final request = RecordedRequest(
      method: method,
      uri: uri,
      headers: headers,
      body: body,
    );
    requests.add(request);
    return (_routes['$method ${uri.path}'] ?? fallback)(request);
  }

  @override
  void close() {}
}

/// The default [FakeDiscordTransport.fallback].
DiscordHttpResponse notFound(RecordedRequest request) =>
    jsonResponse({'message': 'Not routed by the test'}, statusCode: 404);

/// A response with [payload] as its JSON body.
DiscordHttpResponse jsonResponse(Object? payload, {int statusCode = 200}) =>
    DiscordHttpResponse(
      statusCode: statusCode,
      headers: const {},
      body: jsonEncode(payload),
    );

/// A guild text channel as a gateway payload carries it.
Map<String, Object?> rawChannel({
  required String id,
  required String name,
  String? lastMessageId,
}) => {
  'id': id,
  'type': 0,
  'name': name,
  'last_message_id': lastMessageId,
  'permission_overwrites': <Object?>[],
};

/// A guild as READY carries it, with only the `@everyone` role.
///
/// [everyonePermissions] is Discord's decimal bit field. The default is view
/// channel only; pass more to open the composer's controls.
Map<String, Object?> rawGuild({
  required String id,
  required String name,
  required List<Object?> channels,
  String everyonePermissions = '1024',
}) => {
  'id': id,
  'name': name,
  'roles': [
    {'id': id, 'name': '@everyone', 'permissions': everyonePermissions},
  ],
  'channels': channels,
};

/// A message as `MESSAGE_CREATE` and the history route carry it.
Map<String, Object?> rawMessage({
  required String id,
  required String channelId,
  required String authorId,
  required String content,
  String? guildId,
  String timestamp = '2026-07-25T10:00:00+00:00',
}) => {
  'id': id,
  'channel_id': channelId,
  'guild_id': ?guildId,
  'author': {'id': authorId, 'username': 'user-$authorId'},
  'content': content,
  'timestamp': timestamp,
};
