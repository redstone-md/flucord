import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flucord/src/data/chat_image_cache.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real image host and a real disk for the chat image cache of a test file.
///
/// The cache is one object for the whole process and it remembers its folder,
/// so one [ChatImageDisk] serves a whole test file. Call [declare] once, at the
/// top of `main`. Each test serves its pictures under its own path, because the
/// cache may still hold what an earlier test fetched.
final class ChatImageDisk {
  ChatImageDisk._();

  /// Sets up the host and the folder for the test file it is called in.
  factory ChatImageDisk.declare() {
    final disk = ChatImageDisk._();
    setUpAll(disk._open);
    tearDownAll(disk._close);
    return disk;
  }

  /// Written after the end of each picture. A decoder stops before it, so a
  /// test can find a picture's bytes on disk by this text.
  static const pictureMark = 'the-private-bytes-of-a-picture';

  static const _pathProvider = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  final Map<String, Uint8List> _pictures = {};
  late final Directory _home;
  late final HttpServer _server;

  /// Every picture request that reached the host, oldest first.
  final List<Uri> requests = [];

  /// A 3000 by 2000 picture, far larger than any embed draws it.
  late final Uint8List largePhoto;

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> _open() async {
    _home = Directory.systemTemp.createTempSync('flucord-chat-images-');
    _messenger.setMockMethodCallHandler(_pathProvider, (_) async => _home.path);
    // The test binding answers every request with 400. These go to [_server].
    HttpOverrides.global = null;
    // Made here, not inside a test. A future keeps the zone it was made in, and
    // the fake zone of a test that has ended never runs its work again.
    ChatImageCache.instance;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_answer);
    largePhoto = _marked(await _png(3000, 2000));
  }

  Future<void> _close() async {
    await _server.close(force: true);
    _messenger.setMockMethodCallHandler(_pathProvider, null);
    _home.deleteSync(recursive: true);
  }

  Future<void> _answer(HttpRequest request) async {
    requests.add(request.uri);
    final picture = _pictures[request.uri.path];
    if (picture == null) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(picture);
    }
    await request.response.close();
  }

  /// Makes the host answer [path] with [picture], and returns its address.
  String serve(String path, Uint8List picture) {
    _pictures[path] = picture;
    return addressOf(path);
  }

  /// The address of [path] on the host, whether or not it serves anything.
  String addressOf(String path) => 'http://127.0.0.1:${_server.port}$path';

  /// The requests the host answered for [path].
  List<Uri> requestsFor(String path) => [
    for (final request in requests)
      if (request.path == path) request,
  ];

  /// Every file under the cache's folders, as text.
  ///
  /// Read the files, not the cache: what counts is what stays on the machine.
  String get bytesOnDisk => [
    for (final file in _home.listSync(recursive: true).whereType<File>())
      latin1.decode(file.readAsBytesSync()),
  ].join();

  /// Moves the fake clock and the real event loop until [done] is true.
  ///
  /// A picture needs both: its socket and its file work on the real loop, and
  /// their answers run in the test's fake zone, which only a pump flushes.
  Future<void> waitUntil(
    WidgetTester tester,
    bool Function() done,
    String what,
  ) async {
    for (var round = 0; round < 400 && !done(); round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(done(), isTrue, reason: 'Never saw $what.');
  }

  /// Lets the timers of the download end, which a test must do before it ends.
  ///
  /// They run on the fake clock. The cache plans a cleanup 10 seconds after each
  /// read, and the HTTP client drops an idle connection after 15 seconds.
  ///
  /// The real loop goes first, and more than once, because the last steps of a
  /// download start those timers.
  Future<void> letTimersEnd(WidgetTester tester) async {
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(seconds: 16));
    }
  }

  /// A GIF that shows red for 100 ms, and then blue.
  ///
  /// It is written out by hand, because nothing in the test tools encodes a GIF.
  static final Uint8List redThenBlueGif = _marked(
    Uint8List.fromList([
      ...ascii.encode('GIF89a'),
      1, 0, 1, 0, 0x80, 0, 0, // One pixel, with a table of two colours.
      0xff, 0, 0, 0, 0, 0xff, // Red, blue.
      ...ascii.encode('!'), 0xf9, 4, 0, 10, 0, 0, 0, // Wait 100 ms.
      ...ascii.encode(','), 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, //
      2, 0x44, 0x01, 0, // Colour 0.
      ...ascii.encode('!'), 0xf9, 4, 0, 10, 0, 0, 0, // Wait 100 ms.
      ...ascii.encode(','), 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, //
      2, 0x4c, 0x01, 0, // Colour 1.
      ...ascii.encode(';'),
    ]),
  );

  static Uint8List _marked(Uint8List picture) =>
      Uint8List.fromList([...picture, ...latin1.encode(pictureMark)]);

  static Future<Uint8List> _png(int width, int height) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xff3060a0), BlendMode.src);
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}
