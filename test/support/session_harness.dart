import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flucord/src/app.dart';
import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/accessibility.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/chat_repository_factory.dart';
import 'package:flucord/src/domain/credential_vault.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/discord_session.dart';
import 'package:flucord/src/domain/voice_message_recorder.dart';
import 'package:flucord/src/presentation/widgets/destructive_confirmation.dart';

import 'fake_discord_wire.dart';
import 'zoomed_app.dart';

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
    this._diskDirectory,
    this._voiceMessageRecorder,
    this._accessibility,
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

  final WidgetTester _tester;
  final MemoryDesktopWebSocketConnector _connector;
  final _MemoryCredentialVault _vault = _MemoryCredentialVault();

  /// Where the cache lives when the test asked for `onDisk`.
  final Directory? _diskDirectory;
  final VoiceMessageRecorder? _voiceMessageRecorder;
  final AccessibilitySettings _accessibility;

  /// The HTTP side: add routes with [FakeDiscordTransport.on], read what went
  /// out in [FakeDiscordTransport.requests].
  final FakeDiscordTransport transport;

  int _sequence = 0;

  /// The saved token of [accountId]. It is made up, in Discord's shape: its first
  /// part is the account's id.
  static String tokenOf(String accountId) =>
      '${base64Url.encode(utf8.encode(accountId))}.harness.token';

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
            '${DiscordPermissions.viewChannel | DiscordPermissions.sendMessages | DiscordPermissions.readMessageHistory | DiscordPermissions.addReactions | DiscordPermissions.attachFiles | DiscordPermissions.embedLinks}',
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
        chatRepositoryFactory: _FakeWireRepositoryFactory(
          transport,
          _connector,
          _diskDirectory,
        ),
      ),
    ),
  );

  /// Launches the app and walks the session through HELLO, IDENTIFY and READY.
  Future<void> _start(Map<String, Object?> ready) async {
    final dialled = sockets.length;
    await _launch();
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
    _vault.saveAccount(accountId);
    await _start(ready);
  }

  /// Quits the app and opens it again as [accountId], with Discord answering
  /// 503 to the first call a launch makes. Nothing is on the wire after this.
  Future<void> relaunchUnreachable({String accountId = currentUserId}) async {
    await _end();
    _vault.saveAccount(accountId);
    transport.on(
      'GET',
      '/api/v9/gateway',
      (_) => jsonResponse({'message': 'Unavailable'}, statusCode: 503),
    );
    await _launch();
    await settle();
  }

  /// Signs out as the user does, through the Connections dialog.
  Future<void> signOut() async {
    await _tester.tap(find.byKey(const ValueKey('open-connections')));
    await settle();
    await _tester.tap(find.text('Sign out'));
    await settle();
    await _tester.tap(find.byKey(destructiveConfirmKey));
    await settle();
  }

  /// Every byte the cache has on disk, as text, with its side files.
  ///
  /// Read the files, not the tables: SQLite keeps a deleted row's bytes in the
  /// file until something writes over them, and a query cannot see those.
  String get cacheBytesOnDisk => [
    for (final file in _diskDirectory!.listSync().whereType<File>())
      latin1.decode(file.readAsBytesSync()),
  ].join();

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

  Future<void> _settleUntil(bool Function() condition, String what) async {
    for (var attempt = 0; attempt < 10 && !condition(); attempt++) {
      await settle();
    }
    expect(condition(), isTrue, reason: 'The client never produced $what.');
  }
}

/// Defines a widget test that runs inside a started [SessionHarness].
///
/// [ready] replaces [SessionHarness.defaultReady]. [routes] adds HTTP routes
/// before the first request; after that, use `session.transport.on`. Pass a
/// [voiceMessageRecorder] for the composer's voice message button, which only
/// shows with one. [onDisk] keeps the cache in a temporary folder instead of in
/// memory, which a test of a relaunch or of the cache file needs.
/// [accessibility] is what the zoom and font dials are set to at launch.
void testSession(
  String description,
  Future<void> Function(WidgetTester tester, SessionHarness session) body, {
  Map<String, Object?>? ready,
  void Function(FakeDiscordTransport transport)? routes,
  Size size = const Size(1440, 900),
  VoiceMessageRecorder? voiceMessageRecorder,
  bool onDisk = false,
  AccessibilitySettings accessibility = AccessibilitySettings.off,
}) {
  testWidgets(description, (tester) async {
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
    );
    try {
      await session._start(ready ?? SessionHarness.defaultReady());
      await body(tester, session);
    } finally {
      await session._end();
    }
  });
}

final _channelHistoryPath = RegExp(r'^/api/v9/channels/\d+/messages$');

/// Every channel opens on an empty history unless a test routes it, because a
/// 404 here would draw the error view instead of the timeline.
DiscordHttpResponse _emptyHistoryOrNotFound(RecordedRequest request) =>
    request.method == 'GET' && _channelHistoryPath.hasMatch(request.uri.path)
    ? jsonResponse(<Object?>[])
    : notFound(request);

/// Builds the same repository as `DiscordRepositoryFactory`, on the fake wire.
final class _FakeWireRepositoryFactory implements ChatRepositoryFactory {
  const _FakeWireRepositoryFactory(
    this._transport,
    this._connector,
    this._diskDirectory,
  );

  final FakeDiscordTransport _transport;
  final MemoryDesktopWebSocketConnector _connector;
  final Directory? _diskDirectory;

  // No isolate: the widget tester's fake clock would never see an isolate's
  // answer, so the cache has to run on the test's own event loop.
  Future<SqliteChatCache> _openCache() => SqliteChatCache.openAt(
    _diskDirectory == null
        ? inMemoryDatabasePath
        : '${_diskDirectory.path}/flucord.sqlite3',
    factory: databaseFactoryFfiNoIsolate,
  );

  @override
  Future<ChatRepository> create(DiscordAccountSession session) async {
    final desktop = session as DiscordDesktopUserSession;
    const profile = DiscordDesktopProtocolProfile.installedStable20260725;
    final context = DiscordDesktopClientContext.create(profile: profile);
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
      await _openCache(),
      accountId: session.accountId,
    );
  }

  @override
  Future<void> clearCache() async {
    final cache = await _openCache();
    await cache.clear();
    await cache.close();
  }
}

/// A saved session, so the app connects at launch as it does for a real user.
final class _MemoryCredentialVault implements CredentialVault {
  DiscordAccountSession? _session = _sessionOf(SessionHarness.currentUserId);

  static DiscordAccountSession _sessionOf(String accountId) =>
      DiscordDesktopUserSession(SessionHarness.tokenOf(accountId));

  void saveAccount(String accountId) => _session = _sessionOf(accountId);

  @override
  Future<DiscordAccountSession?> readDiscordSession() async => _session;

  @override
  Future<void> writeDiscordSession(DiscordAccountSession session) async =>
      _session = session;

  @override
  Future<void> clearDiscordSession() async => _session = null;
}
