import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flucord/src/app.dart';
import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/data/chat_image_cache.dart';
import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/file_navigation_memory_repository.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/accessibility.dart';
import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/chat_repository_factory.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/discord_remote_auth.dart';
import 'package:flucord/src/domain/discord_session.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/domain/navigation_memory.dart';
import 'package:flucord/src/domain/voice_message_recorder.dart';
import 'package:flucord/src/platform/desktop_integration.dart';
import 'package:flucord/src/presentation/widgets/destructive_confirmation.dart';

import 'fake_discord_wire.dart';
import 'recording_database_factory.dart';
import 'zoomed_app.dart';
import 'memory_credential_vault.dart';

/// The whole app, in a real session, driven by raw gateway events (seam A).
///
/// Everything from [FlucordApp] down to [DiscordDesktopChatRepository] and an
/// in-memory SQLite cache is the production code. A saved session is restored
/// the way a launch restores one. Only the websocket and the HTTP transport are
/// fake, so a test sends what Discord would send and reads what the user sees
/// and what went out on the wire.
///
/// Write a test with [testSession], which starts the session and shuts it down:
///
/// ```dart
/// testSession('a message from the wire shows', (tester, session) async {
///   await session.openChannel(SessionHarness.channelId);
///   await session.dispatch('MESSAGE_CREATE', rawMessage(...));
///   expect(session.messageRow('...'), findsOneWidget);
///   expect(session.socket.frames.where((f) => f['op'] == 8), isEmpty);
///   expect(session.transport.requests, isNotEmpty);
/// });
/// ```
///
/// Wait with [settle], not with `tester.pump` or `tester.pumpAndSettle`, after
/// anything that reaches the repository. The widget tester runs on a fake
/// clock, and an `await` on a cancelled stream subscription only finishes on
/// the real event loop, which [settle] lets run.
///
/// A layout overflow fails the test, like any other Flutter error.
///
/// To count widget builds, use `countBuilds` from `build_counter.dart`.
final class SessionHarness {
  SessionHarness._(
    this._tester,
    this.transport,
    this._connector,
    Directory? diskDirectory,
    this._voiceMessageRecorder,
    this._accessibility,
    this._linkAtLaunch,
    this._chatImagesOnDisk, {
    required bool measured,
  }) : _diskDirectory = diskDirectory,
       _navigationMemory = _WatchedNavigationMemory(
         diskDirectory == null
             ? _HeldNavigationMemory()
             : FileNavigationMemoryRepository(
                 directory: () async => diskDirectory,
               ),
       ),
       _factory = _FakeWireRepositoryFactory(
         transport,
         _connector,
         diskDirectory,
         cacheOnIsolate: measured,
         clearChatImages: _chatImagesOnDisk ? ChatImageCache.clear : null,
       );

  /// The account the default READY signs in.
  static const currentUserId = '100000000000000001';

  /// Somebody else in the default READY's guild, and in its DM.
  static const friendId = '100000000000000002';

  static const guildId = '200000000000000001';

  /// The first text channel of [guildId].
  static const channelId = '300000000000000001';

  /// A second text channel of [guildId].
  static const otherChannelId = '300000000000000002';

  /// The DM with [friendId].
  static const dmChannelId = '300000000000000003';

  /// The key a captcha solved in a test hands back.
  static const solvedCaptchaKey = 'harness-captcha-key';

  /// The captcha the app shows. A tap solves it, as a person would.
  static final captchaView = find.byKey(const ValueKey('harness-captcha'));

  final WidgetTester _tester;
  final MemoryDesktopWebSocketConnector _connector;
  final MemoryCredentialVault _vault = MemoryCredentialVault(
    session: _sessionOf(currentUserId),
  );
  late _FakeDesktopWindow _window = _FakeDesktopWindow(_linkAtLaunch);

  /// Where the cache lives when the test asked for `onDisk`.
  final Directory? _diskDirectory;
  final _WatchedNavigationMemory _navigationMemory;
  final _FakeWireRepositoryFactory _factory;
  final VoiceMessageRecorder? _voiceMessageRecorder;
  final AccessibilitySettings _accessibility;
  final ChannelLink? _linkAtLaunch;
  final bool _chatImagesOnDisk;

  /// The HTTP side: add routes with [FakeDiscordTransport.on], read what went
  /// out in [FakeDiscordTransport.requests].
  final FakeDiscordTransport transport;

  final _RecordingLinks _links = _RecordingLinks();

  /// Every link the app opened in the browser, oldest first.
  List<Uri> get openedLinks => _links.opened;

  /// The QR sign-in. Feed it what the phone and Discord would cause.
  final FakeRemoteAuth remoteAuth = FakeRemoteAuth();

  int _sequence = 0;

  /// The saved token of [accountId]. It is made up, in Discord's shape: its first
  /// part is the account's id.
  static String tokenOf(String accountId) =>
      '${base64Url.encode(utf8.encode(accountId))}.harness.token';

  static DiscordAccountSession _sessionOf(String accountId) =>
      DiscordDesktopUserSession(tokenOf(accountId));

  /// The READY a session starts from. A new map each call, so a test can change
  /// its copy and pass it to [testSession].
  static Map<String, Object?> defaultReady() => {
    'session_id': 'harness-session',
    'resume_gateway_url': 'wss://gateway.discord.gg',
    'user': {'id': currentUserId, 'username': 'me'},
    'users': [
      {'id': friendId, 'username': 'friend', 'global_name': 'Friend'},
    ],
    'guilds': [
      rawGuild(
        id: guildId,
        name: 'The Forge',
        channels: [
          rawChannel(id: channelId, name: 'general'),
          rawChannel(id: otherChannelId, name: 'random'),
        ],
        // What an ordinary member can do, so the composer is fully open.
        everyonePermissions:
            '${DiscordPermissions.viewChannel | DiscordPermissions.sendMessages | DiscordPermissions.readMessageHistory | DiscordPermissions.addReactions | DiscordPermissions.attachFiles | DiscordPermissions.embedLinks | DiscordPermissions.sendVoiceMessages}',
      ),
    ],
    'private_channels': [
      {
        'id': dmChannelId,
        'type': 1,
        'recipient_ids': [friendId],
      },
    ],
    'read_state': {'version': 1, 'partial': false, 'entries': <Object?>[]},
    'user_guild_settings': {
      'version': 1,
      'partial': false,
      'entries': <Object?>[],
    },
  };

  /// Pumps a new app that restores the saved session.
  Future<void> _launch() => _tester.pumpWidget(
    FlucordApp(
      bootstrap: AppBootstrap(
        voiceMessageRecorder: _voiceMessageRecorder,
        credentialVault: _vault,
        accessibilityRepository: FixedDials(_accessibility),
        desktopIntegration: _window,
        chatRepositoryFactory: _factory,
        clearChatImages: _chatImagesOnDisk ? null : _noChatImagesToClear,
        discordRemoteAuthGatewayFactory: remoteAuth,
        navigationMemoryRepository: _navigationMemory,
        captcha: _solvableCaptcha,
        externalLinkLauncher: _links,
      ),
    ),
  );

  /// Launches the app. A signed-in launch that can reach Discord goes on to
  /// READY. Any other launch stops at whatever the app shows on its own.
  Future<void> _start(
    Map<String, Object?> ready, [
    SessionLaunch launch = SessionLaunch.signedIn,
  ]) async {
    if (launch == SessionLaunch.unreachable) discordUnreachable();
    if (launch == SessionLaunch.signedOut) await _vault.clearDiscordSession();
    final dialled = sockets.length;
    await _launch();
    switch (launch) {
      case SessionLaunch.signedIn:
        await _walkToReady(ready, dialled);
      case SessionLaunch.unreachable:
        await settleServerErrorRepeats();
      case SessionLaunch.signedOut:
        await settle();
    }
  }

  /// Makes the first call of a connection answer 503, so no socket is dialled.
  void discordUnreachable() => transport.on(
    'GET',
    '/api/v9/gateway',
    (_) => jsonResponse({'message': 'Unavailable'}, statusCode: 503),
  );

  /// Undoes [discordUnreachable].
  void discordReachable() => transport.on(
    'GET',
    '/api/v9/gateway',
    (_) => jsonResponse({'url': 'wss://gateway.discord.gg'}),
  );

  /// Walks a connection the app is about to start through HELLO, IDENTIFY and
  /// READY, up to the first workspace.
  Future<void> connectToReady(Map<String, Object?> ready) =>
      _walkToReady(ready, sockets.length);

  Future<void> _walkToReady(Map<String, Object?> ready, int dialled) async {
    await _settleUntil(() => sockets.length > dialled, 'a socket');
    await hello();
    await _settleUntil(
      () => socket.frames.any((frame) => frame['op'] == 2),
      'IDENTIFY',
    );
    await dispatch('READY', ready);
    // The client waits this long for more opening dispatches before it hands
    // the first workspace to the app.
    await _tester.pump(const Duration(seconds: 2));
    await settle();
  }

  /// Unmounts the app and lets the repository finish closing, so no timer of
  /// the session outlives the test.
  Future<void> _end() async {
    await _tester.pumpWidget(const SizedBox());
    await settle();
    await _settleWhile(() => _navigationMemory.isWriting, 'the last write');
  }

  /// Lets real time pass and pumps in turns while [busy] holds, for work that
  /// waits on a real file.
  ///
  /// A file write finishes on the real event loop, but the code after each
  /// of its awaits runs on the test's fake clock. Awaiting the write inside
  /// one `runAsync` would hang when the file answers late: the rest of the
  /// write waits for a pump, and the pump waits for `runAsync`.
  Future<void> _settleWhile(bool Function() busy, String what) async {
    for (var attempt = 0; attempt < 500 && busy(); attempt++) {
      await _tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await _tester.pump();
    }
    expect(busy(), isFalse, reason: 'The app never finished $what.');
  }

  /// Quits the app and opens it again, signed in as [accountId], up to READY.
  ///
  /// The test must use `onDisk`, or nothing survives the quit. The account can
  /// change here with no sign-out. A real install reaches that state through a
  /// cache left by a version that did not clear it on sign-out.
  Future<void> relaunch({
    String accountId = currentUserId,
    required Map<String, Object?> ready,
  }) async {
    await _end();
    _vault.session = _sessionOf(accountId);
    await _start(ready);
  }

  /// Quits the app and opens it again from [link], as a link does that starts
  /// the app, up to READY.
  Future<void> relaunchWithLink(
    ChannelLink link, {
    required Map<String, Object?> ready,
  }) async {
    await _end();
    _window = _FakeDesktopWindow(link);
    await _start(ready);
  }

  /// Quits the app and opens it again as [accountId], with Discord answering
  /// 503 to the first call a launch makes. Nothing is on the wire after this.
  Future<void> relaunchUnreachable({String accountId = currentUserId}) async {
    await _end();
    _vault.session = _sessionOf(accountId);
    discordUnreachable();
    await _launch();
    await settleServerErrorRepeats();
  }

  /// Lets a GET that keeps answering a server error use up its repeats, which
  /// wait one and then two seconds on the REST client's clock.
  Future<void> settleServerErrorRepeats() async {
    await settle();
    await _tester.pump(const Duration(seconds: 1));
    await settle();
    await _tester.pump(const Duration(seconds: 2));
    await settle();
  }

  /// Signs out as the user does, through the Connections dialog.
  Future<void> signOut() async {
    await _tester.tap(find.byKey(const ValueKey('open-connections')));
    await settle();
    await _tester.tap(find.text('Sign out'));
    await settle();
    await _tester.tap(find.byKey(destructiveConfirmKey));
    await _settleUntil(() => _vault.session == null, 'the end of the sign-out');
  }

  /// Every byte the cache has on disk, as text, with its side files.
  ///
  /// Read the files, not the tables: SQLite keeps a deleted row's bytes in the
  /// file until something writes over them, and a query cannot see those.
  String get cacheBytesOnDisk => [
    for (final file in _diskDirectory!.listSync().whereType<File>())
      latin1.decode(file.readAsBytesSync()),
  ].join();

  /// The app's message toasts so far, oldest first.
  List<DesktopMessageNotification> get toasts => _window.toasts;

  /// Takes the focus from the window, as the platform layer reports it.
  void blurWindow() => _window.setFocused(false);

  /// Gives the window the focus back, as the platform layer reports it.
  void focusWindow() => _window.setFocused(true);

  /// Minimizes the window, as the platform layer reports it, which suspends
  /// the app.
  void minimizeWindow() => _window.setVisible(false);

  /// Brings the minimized window back, as the platform layer reports it.
  void restoreWindow() => _window.setVisible(true);

  /// The dialling side of the fake gateway, to hold a dial in flight.
  MemoryDesktopWebSocketConnector get connector => _connector;

  /// Whether the message with this [id] has reached the disk, as read by a
  /// connection of its own. This is what a launch after a crash would find. The
  /// test must use `onDisk`.
  Future<bool> messageOnDisk(String id) async {
    final found = await _tester.runAsync(() async {
      final reader = await databaseFactoryFfiNoIsolate.openDatabase(
        _factory.diskPath!,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        return await reader.query(
          'messages',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [id],
        );
      } finally {
        await reader.close();
      }
    });
    return found!.isNotEmpty;
  }

  /// How many commits the cache has made in this session.
  int get cacheCommits => _factory.databases.commits;

  /// What the session's open database answers to `PRAGMA name`.
  Future<Object?> cachePragma(String name) async {
    final rows = await _tester.runAsync(
      () => _factory.databases.opened!.rawQuery('PRAGMA $name'),
    );
    return rows!.single.values.single;
  }

  /// The system asks the app to exit, as it does when its window closes. This
  /// lets the real event loop run while the fake clock stands still, so no timer
  /// of the app can have done any work by the time it returns. Call [settle] to
  /// let the app finish, then read [exitAnswer].
  Future<void> systemAsksToExit() async {
    // Not awaited: the answer needs time on the fake clock.
    unawaited(
      _tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.platform.name,
        SystemChannels.platform.codec.encodeMethodCall(
          const MethodCall('System.requestAppExit'),
        ),
        (reply) => exitAnswer = reply == null
            ? null
            : SystemChannels.platform.codec.decodeEnvelope(reply),
      ),
    );
    for (var round = 0; round < 12; round++) {
      await _tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _tester.pump();
    }
  }

  /// What the next launch would read as the navigation memory.
  Future<NavigationMemory?> savedNavigation() async =>
      _tester.runAsync<NavigationMemory?>(_navigationMemory.load);

  /// What the app answered to [systemAsksToExit], once it has.
  Object? exitAnswer;

  /// The message with this [id] in the running session's cache, which is what
  /// the next launch reads. A cache read needs the real event loop.
  Future<ChatMessage?> cachedMessage(String id) => _tester
      .runAsync<ChatMessage?>(() => _factory.openedCache!.readMessage(id));

  /// Removes a row behind the app's back, for a state the wire cannot reach,
  /// such as a cache write that failed earlier.
  Future<void> dropCachedMessage(String id) async =>
      _tester.runAsync(() => _factory.openedCache!.deleteMessage(id));

  /// The socket the client dialled last.
  MemoryDesktopWebSocket get socket => _connector.sockets.last;

  /// Every socket the client dialled, oldest first.
  List<MemoryDesktopWebSocket> get sockets => _connector.sockets;

  /// Sends HELLO on [socket], which is what a new socket needs before the
  /// client sends IDENTIFY or RESUME on it.
  Future<void> hello() async {
    socket.receive({
      'op': 10,
      'd': {'heartbeat_interval': 41250},
    });
    await settle();
  }

  /// Sends one raw gateway dispatch on [socket] and waits for the screen.
  ///
  /// [data] is the `d` field. The sequence number is handled here. Pass
  /// `settle: false` to send many at once, then call [settle] after the last.
  Future<void> dispatch(
    String event,
    Map<String, Object?> data, {
    bool settle = true,
  }) async {
    socket.receive({'op': 0, 's': ++_sequence, 't': event, 'd': data});
    if (settle) await this.settle();
  }

  /// One dispatch as a JSON frame, for `socket.receiveRaw`. It takes its
  /// sequence number now, so encode frames in the order they will be sent.
  String encodeDispatch(String event, Map<String, Object?> data) =>
      jsonEncode({'op': 0, 's': ++_sequence, 't': event, 'd': data});

  /// The sequence number of the last dispatch [dispatch] sent.
  int get sequence => _sequence;

  /// Opens a channel of [space] by tapping the server and the channel, as the
  /// user does.
  Future<void> openChannel(String id, {String space = guildId}) async {
    await _tester.tap(find.byKey(ValueKey('space-$space')));
    await settle();
    await _tester.tap(find.byKey(ValueKey('channel-$id')));
    await settle();
  }

  /// Finds the timeline row of the message with this [id].
  Finder messageRow(String id) => find.byKey(ValueKey('message-$id'));

  /// Lets about 300 ms pass on the fake clock, and lets the real event loop run
  /// between frames.
  ///
  /// It does not use `pumpAndSettle`, which never returns while a spinner
  /// turns. Call that as well when a test needs a long animation to end.
  Future<void> settle() async {
    for (var round = 0; round < 12; round++) {
      await _tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _tester.pump(const Duration(milliseconds: 25));
    }
  }

  /// Settles until [condition] holds, for a large frame on its worker isolate.
  /// That takes real time, which [settle] alone does not wait for.
  Future<void> settleUntilDecoded(bool Function() condition) async {
    for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
      await _tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await settle();
    }
    expect(condition(), isTrue, reason: 'The large frame never landed.');
  }

  Future<void> _settleUntil(bool Function() condition, String what) async {
    for (var attempt = 0; attempt < 10 && !condition(); attempt++) {
      await settle();
    }
    expect(condition(), isTrue, reason: 'The client never produced $what.');
  }
}

/// How a [testSession] opens the app.
enum SessionLaunch {
  /// A saved session that reaches READY.
  signedIn,

  /// A saved session, with Discord out of reach.
  unreachable,

  /// Nothing saved: a new user.
  signedOut,
}

/// Defines a widget test that runs inside a started [SessionHarness].
///
/// [ready] replaces [SessionHarness.defaultReady]. [routes] adds HTTP routes
/// before the first request; after that, use `session.transport.on`. Pass a
/// [voiceMessageRecorder] for the composer's voice message button, which only
/// shows with one. [onDisk] keeps the cache in a temporary folder instead of in
/// memory, which a test of a relaunch or of the cache file needs. [linkAtLaunch]
/// reaches the app when it attaches to the desktop, before any workspace exists,
/// as a link does that started the app.
/// Pass a [platform] when a test depends on platform gestures, such as the right
/// button on selectable text. Without one, Flutter tests run as Android.
/// [accessibility] is what the zoom and font dials are set to at launch.
/// Pass [measured] for a run on a real clock that records frame times. The app
/// then does what it does for a user: it builds no semantics tree, since no
/// screen reader is on, and the cache works on its own isolate.
/// [chatImagesOnDisk] makes a sign-out clear the real chat image cache, which
/// needs a `ChatImageDisk` declared in the test file.
void testSession(
  String description,
  Future<void> Function(WidgetTester tester, SessionHarness session) body, {
  Map<String, Object?>? ready,
  void Function(FakeDiscordTransport transport)? routes,
  Size size = const Size(1440, 900),
  SessionLaunch launch = SessionLaunch.signedIn,
  VoiceMessageRecorder? voiceMessageRecorder,
  bool onDisk = false,
  AccessibilitySettings accessibility = AccessibilitySettings.off,
  ChannelLink? linkAtLaunch,
  TargetPlatform? platform,
  bool measured = false,
  bool chatImagesOnDisk = false,
}) {
  testWidgets(description, semanticsEnabled: !measured, (tester) async {
    // Outside debug builds, this setter throws even for null.
    if (platform != null) debugDefaultTargetPlatformOverride = platform;
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transport = FakeDiscordTransport(fallback: _emptyHistoryOrNotFound);
    routes?.call(transport);
    final disk = onDisk
        ? Directory.systemTemp.createTempSync('flucord-session-')
        : null;
    if (disk != null) addTearDown(() => disk.deleteSync(recursive: true));
    final session = SessionHarness._(
      tester,
      transport,
      MemoryDesktopWebSocketConnector(),
      disk,
      voiceMessageRecorder,
      accessibility,
      linkAtLaunch,
      chatImagesOnDisk,
      measured: measured,
    );
    try {
      await session._start(ready ?? SessionHarness.defaultReady(), launch);
      await body(tester, session);
    } finally {
      await session._end();
      if (platform != null) debugDefaultTargetPlatformOverride = null;
    }
  });
}

/// Stands in for the hCaptcha view, which needs WebView2: one button that
/// solves the captcha with [SessionHarness.solvedCaptchaKey].
Widget _solvableCaptcha(
  DiscordRemoteAuthCaptchaChallenge challenge,
  Future<void> Function(String key) onSolved,
) => TextButton(
  key: const ValueKey('harness-captcha'),
  onPressed: () => onSolved(SessionHarness.solvedCaptchaKey),
  child: const Text('Solve the captcha'),
);

/// A test with no folder for the chat image cache has nothing in it to clear.
Future<void> _noChatImagesToClear() async {}

final _channelHistoryPath = RegExp(r'^/api/v9/channels/\d+/messages$');

/// Every channel opens on an empty history unless a test routes it, because a
/// 404 here would draw the error view instead of the timeline.
DiscordHttpResponse _emptyHistoryOrNotFound(RecordedRequest request) =>
    request.method == 'GET' && _channelHistoryPath.hasMatch(request.uri.path)
    ? jsonResponse(<Object?>[])
    : notFound(request);

/// Builds the same repository as `DiscordRepositoryFactory`, on the fake wire.
final class _FakeWireRepositoryFactory implements ChatRepositoryFactory {
  _FakeWireRepositoryFactory(
    this._transport,
    this._connector,
    this._diskDirectory, {
    required bool cacheOnIsolate,
    required Future<void> Function()? clearChatImages,
  }) : _cacheOnIsolate = cacheOnIsolate,
       _clearChatImages = clearChatImages;

  final FakeDiscordTransport _transport;
  final MemoryDesktopWebSocketConnector _connector;
  final Directory? _diskDirectory;
  final bool _cacheOnIsolate;
  final Future<void> Function()? _clearChatImages;

  /// The cache of the repository built last.
  SqliteChatCache? openedCache;

  // No isolate: the widget tester's fake clock would never see an isolate's
  // answer, so the cache has to run on the test's own event loop.
  final RecordingDatabaseFactory databases = RecordingDatabaseFactory(
    databaseFactoryFfiNoIsolate,
  );

  /// The cache file, when the test asked for `onDisk`.
  String? get diskPath =>
      _diskDirectory == null ? null : '${_diskDirectory.path}/flucord.sqlite3';

  // On its isolate, the cache is the production one, with the production
  // factory. Its work leaves the UI thread either way, so memory or a file makes
  // no difference to frame times.
  Future<SqliteChatCache> _openCache() => SqliteChatCache.openAt(
    diskPath ?? inMemoryDatabasePath,
    factory: _cacheOnIsolate ? null : databases,
  );

  @override
  Future<ChatRepository> create(DiscordAccountSession session) async {
    final desktop = session as DiscordDesktopUserSession;
    const profile = DiscordDesktopProtocolProfile.installedStable20260725;
    final context = DiscordDesktopClientContext.create(profile: profile);
    final cache = openedCache = await _openCache();
    return DiscordDesktopChatRepository(
      DiscordDesktopApiClient(
        authorization: desktop.transportCredential,
        headers: context.authenticatedHeaders(desktop.transportCredential),
        baseUri: profile.apiBaseUri,
        transport: _transport,
      ),
      DiscordDesktopGatewayClient(
        authorization: desktop.transportCredential,
        properties: context.superProperties.toJson(),
        profile: profile,
        socketConnector: _connector,
      ),
      cache,
      accountId: session.accountId,
      clearChatImages: _clearChatImages,
    );
  }

  @override
  Future<void> clearCache() async {
    final cache = await _openCache();
    await cache.clear();
    await cache.close();
  }
}

/// The desktop window as the app sees it, through the seam the platform layer
/// uses. It keeps each message the app asks to show as a toast. Whether the
/// window has focus does not matter for those, so the desktop's own filter is
/// left out.
final class _FakeDesktopWindow implements DesktopIntegration {
  _FakeDesktopWindow(this._linkAtLaunch);

  final ChannelLink? _linkAtLaunch;
  final List<DesktopMessageNotification> toasts = [];
  late DesktopAppSurface _surface;
  StreamSubscription<DesktopMessageNotification>? _subscription;

  void setFocused(bool value) => _surface.setApplicationActive(value);

  void setVisible(bool value) => _surface.setWindowVisible(value);

  @override
  Future<void> initialize() async {}

  @override
  void attach(DesktopAppSurface surface) {
    _surface = surface;
    _subscription = surface.messageNotifications.listen(toasts.add);
    final link = _linkAtLaunch;
    if (link != null) surface.openChannelLink(link);
  }

  @override
  Future<void> dispose() async => _subscription?.cancel();
}

/// The browser, as far as the app can tell: it keeps each link and says it
/// opened.
final class _RecordingLinks implements ExternalLinkLauncher {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

/// The QR sign-in, below the app's controller. It stands in for the phone and
/// for Discord's remote-auth socket, which encrypts its frames per session.
final class FakeRemoteAuth
    implements DiscordRemoteAuthGatewayFactory, DiscordRemoteAuthGateway {
  final StreamController<DiscordRemoteAuthEvent> _events =
      StreamController.broadcast();

  /// How many sign-ins the app started.
  int starts = 0;

  /// Delivers one event to the sign-in the app has open.
  void add(DiscordRemoteAuthEvent event) => _events.add(event);

  @override
  DiscordRemoteAuthGateway create() => this;

  @override
  Stream<DiscordRemoteAuthEvent> get events => _events.stream;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> submitCaptcha(String response) async {}

  // Stays open: the app closes a gateway before it starts the next one, and
  // this one object plays every gateway of the session.
  @override
  Future<void> close() async {}
}

/// The navigation memory with no file behind it, for a test not on disk. It still
/// lasts through a relaunch.
final class _HeldNavigationMemory implements NavigationMemoryRepository {
  NavigationMemory? _held;

  @override
  Future<NavigationMemory?> load() async => _held;

  @override
  Future<void> save(NavigationMemory memory) async => _held = memory;

  @override
  Future<void> clear() async => _held = null;
}

/// Knows whether a write is still running, because a write to a real file
/// finishes on the real event loop, and a relaunch must find it done.
final class _WatchedNavigationMemory implements NavigationMemoryRepository {
  _WatchedNavigationMemory(this._inner);

  final NavigationMemoryRepository _inner;
  int _writes = 0;

  bool get isWriting => _writes > 0;

  @override
  Future<NavigationMemory?> load() => _inner.load();

  @override
  Future<void> save(NavigationMemory memory) => _watch(_inner.save(memory));

  @override
  Future<void> clear() => _watch(_inner.clear());

  Future<void> _watch(Future<void> write) {
    _writes++;
    return write.whenComplete(() => _writes--);
  }
}

/// A saved session, so the app connects at launch as it does for a real user.
