import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/presentation/widgets/pending_attachment_strip.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _sendPath = '/api/v9/channels/${SessionHarness.channelId}/messages';

/// A one pixel BMP, which is the format the clipboard plugin reads on Windows.
final _onePixelBmp = Uint8List.fromList([
  ...ascii.encode('BM'), 58, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, //
  40, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 24, 0, //
  0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
  0, 0, 255, 0, //
]);

void main() {
  group('dropping files', () {
    testSession('adds each of them to the strip', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      final folder = _tempFolder();

      await _drop(tester, session, [
        _file(folder, 'notes.txt', 5),
        _file(folder, 'photo.png', 7),
      ]);

      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('photo.png'), findsOneWidget);
    });

    testSession(
      'refuses a file over the limit with the picker\'s message',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        final folder = _tempFolder();
        final huge = File(p.join(folder.path, 'huge.bin'));
        final open = huge.openSync(mode: FileMode.write);
        open.truncateSync(21 * 1024 * 1024);
        open.closeSync();

        await _drop(tester, session, [
          huge.path,
          _file(folder, 'small.txt', 5),
        ]);

        expect(find.text('huge.bin'), findsNothing);
        expect(find.text('small.txt'), findsOneWidget);
        expect(
          find.text('That file is above the 20 MB upload limit.'),
          findsOneWidget,
        );
      },
      // An account with no subscription has the smallest limit: 20 MB.
      routes: (transport) => transport.on(
        'GET',
        '/api/v9/users/@me/entitlements',
        (_) => jsonResponse(<Object?>[]),
      ),
    );

    testSession('skips a folder', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      final folder = _tempFolder();

      await _drop(tester, session, [
        folder.path,
        _file(folder, 'notes.txt', 5),
      ]);

      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text(p.basename(folder.path)), findsNothing);
    });

    testSession('does nothing behind a dialog', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      final folder = _tempFolder();
      await tester.tap(find.byKey(const ValueKey('composer-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-poll')));
      await tester.pumpAndSettle();

      await _drop(tester, session, [_file(folder, 'notes.txt', 5)]);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('notes.txt'), findsNothing);
    });

    testSession(
      'does nothing without the attach permission',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        final folder = _tempFolder();

        await _drop(tester, session, [_file(folder, 'notes.txt', 5)]);

        expect(find.text('notes.txt'), findsNothing);
      },
      ready: _readyDenyingAttachments(),
    );
  });

  group('pasting', () {
    testSession('a copied image attaches it, and it goes out as a PNG', (
      tester,
      session,
    ) async {
      session.transport.on(
        'POST',
        _sendPath,
        (_) => jsonResponse(
          rawMessage(
            id: '900000000000000001',
            channelId: SessionHarness.channelId,
            guildId: SessionHarness.guildId,
            authorId: SessionHarness.currentUserId,
            content: '',
          ),
        ),
      );
      await session.openChannel(SessionHarness.channelId);
      _clipboardHolds(tester, image: _onePixelBmp);

      await _pressPaste(tester, session);
      await _waitFor(tester, session, find.text('image.png'));
      final keptAt = tester
          .widget<PendingAttachmentStrip>(find.byType(PendingAttachmentStrip))
          .attachments
          .single
          .path;
      expect(File(keptAt).existsSync(), isTrue);

      await tester.tap(find.byKey(const ValueKey('send-message')));
      await session.settle();

      final body = latin1.decode(
        session.transport.requests
            .singleWhere((r) => r.method == 'POST' && r.uri.path == _sendPath)
            .body!,
      );
      expect(body, contains('filename="image.png"'));
      expect(body, contains('\x89PNG'));
      expect(find.text('image.png'), findsNothing);
      expect(File(keptAt).existsSync(), isFalse);
    });

    testSession('a failed picture stays on disk until it is deleted', (
      tester,
      session,
    ) async {
      session.transport.on(
        'POST',
        _sendPath,
        (_) => jsonResponse({
          'code': 50013,
          'message': 'Missing Permissions',
        }, statusCode: 403),
      );
      await session.openChannel(SessionHarness.channelId);
      _clipboardHolds(tester, image: _onePixelBmp);
      await _pressPaste(tester, session);
      await _waitFor(tester, session, find.text('image.png'));
      final keptAt = tester
          .widget<PendingAttachmentStrip>(find.byType(PendingAttachmentStrip))
          .attachments
          .single
          .path;

      await tester.tap(find.byKey(const ValueKey('send-message')));
      await session.settle();
      expect(find.byKey(const ValueKey('outgoing-discard')), findsOneWidget);
      expect(File(keptAt).existsSync(), isTrue);

      await tester.tap(find.byKey(const ValueKey('outgoing-discard')));
      await session.settle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(File(keptAt).existsSync(), isFalse);
    });

    testSession('a picture that never went out is gone after sign-out', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      _clipboardHolds(tester, image: _onePixelBmp);
      await _pressPaste(tester, session);
      await _waitFor(tester, session, find.text('image.png'));
      final keptAt = tester
          .widget<PendingAttachmentStrip>(find.byType(PendingAttachmentStrip))
          .attachments
          .single
          .path;

      await session.signOut();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(File(keptAt).existsSync(), isFalse);
    });

    testSession('a picture taken off the strip is gone from disk', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      _clipboardHolds(tester, image: _onePixelBmp);
      await _pressPaste(tester, session);
      await _waitFor(tester, session, find.text('image.png'));
      final keptAt = tester
          .widget<PendingAttachmentStrip>(find.byType(PendingAttachmentStrip))
          .attachments
          .single
          .path;

      await tester.tap(find.byTooltip('Remove attachment'));
      await session.settle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(find.byType(PendingAttachmentStrip), findsNothing);
      expect(File(keptAt).existsSync(), isFalse);
    });

    testSession('text puts it in the box, as before', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      _clipboardHolds(tester, text: 'copied words');

      await _pressPaste(tester, session);

      expect(_boxText(tester), 'copied words');
      expect(find.byType(PendingAttachmentStrip), findsNothing);
    });

    testSession('text with a picture beside it pastes the text', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      _clipboardHolds(tester, text: 'a table cell', image: _onePixelBmp);

      await _pressPaste(tester, session);

      expect(_boxText(tester), 'a table cell');
      expect(find.byType(PendingAttachmentStrip), findsNothing);
    });

    testSession('files copied in a file manager attaches them', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      final folder = _tempFolder();
      _clipboardHolds(tester, files: [_file(folder, 'photo.png', 7)]);

      await _pressPaste(tester, session);

      expect(find.text('photo.png'), findsOneWidget);
    });

    testSession('and leaving the channel while it reads keeps it out of '
        'the next', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      final folder = _tempFolder();
      final files = Completer<List<String>>();
      _clipboardHolds(tester, filesAnswer: files.future);

      await _pressPaste(tester, session);
      await session.openChannel(SessionHarness.otherChannelId);
      files.complete([_file(folder, 'photo.png', 7)]);
      await session.settle();

      expect(find.text('photo.png'), findsNothing);
    });

    testSession(
      'attaches nothing without the attach permission',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        _clipboardHolds(tester, image: _onePixelBmp);

        await _pressPaste(tester, session);

        expect(find.byType(PendingAttachmentStrip), findsNothing);
      },
      ready: _readyDenyingAttachments(),
    );
  });
}

/// Without the account's member record the client cannot judge permissions and
/// allows everything, so this READY has to carry one.
Map<String, Object?> _readyDenyingAttachments() => SessionHarness.defaultReady()
  ..['users'] = [
    {'id': SessionHarness.currentUserId, 'username': 'me'},
  ]
  ..['private_channels'] = <Object?>[]
  ..['merged_members'] = [
    [
      {'user_id': SessionHarness.currentUserId, 'roles': <String>[]},
    ],
  ]
  ..['guilds'] = [
    rawGuild(
      id: SessionHarness.guildId,
      name: 'The Forge',
      channels: [
        {
          ...rawChannel(id: SessionHarness.channelId, name: 'general'),
          'permission_overwrites': [
            {
              'id': SessionHarness.guildId,
              'type': 0,
              'allow': '0',
              'deny': '${DiscordPermissions.attachFiles}',
            },
          ],
        },
      ],
      everyonePermissions:
          '${DiscordPermissions.viewChannel | DiscordPermissions.sendMessages | DiscordPermissions.readMessageHistory | DiscordPermissions.attachFiles}',
    ),
  ];

Directory _tempFolder() {
  final folder = Directory.systemTemp.createTempSync('flucord-test-');
  addTearDown(() => folder.deleteSync(recursive: true));
  return folder;
}

String _file(Directory folder, String name, int size) {
  final file = File(p.join(folder.path, name));
  file.writeAsBytesSync(List.filled(size, 7));
  return file.path;
}

/// Sends what the native side sends when the user lets go of files over the
/// window.
Future<void> _drop(
  WidgetTester tester,
  SessionHarness session,
  List<String> paths,
) async {
  const codec = StandardMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'desktop_drop',
    codec.encodeMethodCall(MethodCall('performOperation', paths)),
    (_) {},
  );
  await session.settle();
}

/// Answers as the system does for the clipboard's contents.
void _clipboardHolds(
  WidgetTester tester, {
  String? text,
  Uint8List? image,
  List<String> files = const [],
  Future<List<String>>? filesAnswer,
}) {
  final messenger = tester.binding.defaultBinaryMessenger;
  const pasteboard = MethodChannel('pasteboard');
  messenger
    ..setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.hasStrings' => {'value': text != null},
        'Clipboard.getData' => text == null ? null : {'text': text},
        _ => null,
      },
    )
    ..setMockMethodCallHandler(
      pasteboard,
      (call) async => switch (call.method) {
        'files' => filesAnswer ?? files,
        'image' => _nativeImageAnswer(image),
        _ => null,
      },
    );
  addTearDown(() {
    messenger
      ..setMockMethodCallHandler(SystemChannels.platform, null)
      ..setMockMethodCallHandler(pasteboard, null);
  });
}

/// The plugin's native side hands over a temp file on Windows, and the bytes
/// on every other platform.
Object? _nativeImageAnswer(Uint8List? image) {
  if (image == null || !Platform.isWindows) return image;
  final file = File(p.join(_tempFolder().path, 'pasteboard.tmp'));
  file.writeAsBytesSync(image);
  return file.path;
}

Future<void> _pressPaste(WidgetTester tester, SessionHarness session) async {
  await tester.tap(find.byKey(const ValueKey('message-composer')));
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await session.settle();
}

String _boxText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('message-composer')))
    .controller!
    .text;

/// Turning a picture into a PNG runs on the engine's threads, so it takes real
/// time, which the fake clock does not move.
Future<void> _waitFor(
  WidgetTester tester,
  SessionHarness session,
  Finder finder,
) async {
  for (var round = 0; round < 100 && finder.evaluate().isEmpty; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await session.settle();
  }
  expect(finder, findsOneWidget);
}
