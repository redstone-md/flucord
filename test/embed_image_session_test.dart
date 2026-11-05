import 'dart:ui' as ui;

import 'package:flucord/src/data/discord/discord_user_settings_proto.dart';
import 'package:flucord/src/data/proto/proto_message.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_image_disk.dart';
import 'support/fake_discord_wire.dart';
import 'support/flucord_icon_finder.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000001';

/// A message in the DM the app opens at launch, with one embed made of [embed].
Map<String, Object?> _messageWithEmbed(Map<String, Object?> embed) => {
  ...rawMessage(
    id: _messageId,
    channelId: SessionHarness.dmChannelId,
    authorId: SessionHarness.friendId,
    content: 'look at this',
  ),
  'embeds': [
    {'type': 'rich', ...embed},
  ],
};

/// The media field of an embed, served by a media proxy at [proxyUrl].
Map<String, Object?> _media(
  String proxyUrl, {
  int width = 3000,
  int height = 2000,
}) => {
  'url': 'https://pictures.example/original',
  'proxy_url': proxyUrl,
  'width': width,
  'height': height,
};

final _embedImage = find.byKey(const ValueKey('embed-image'));

/// The picture the embed draws right now, if it has arrived.
RawImage _drawn(WidgetTester tester, [Finder? image]) =>
    tester.widget<RawImage>(
      find.descendant(
        of: image ?? _embedImage,
        matching: find.byType(RawImage),
      ),
    );

void main() {
  final images = ChatImageDisk.declare();

  testSession(
    'a large embed image is asked for and decoded at the size it is drawn',
    (tester, session) async {
      const path = '/external/large/photo.png';
      final address = images.serve(path, images.largePhoto);

      await session.dispatch(
        'MESSAGE_CREATE',
        _messageWithEmbed({'image': _media(address)}),
      );
      await images.waitUntil(
        tester,
        () => _drawn(tester).image != null,
        'the embed image',
      );

      // The photo is 3:2, so the 420 by 300 box draws it at 420 by 280.
      final scale = tester.view.devicePixelRatio;
      final width = (420 * scale).round();
      final height = (280 * scale).round();
      final request = images.requestsFor(path).single;
      expect(request.queryParameters['width'], '$width');
      expect(request.queryParameters['height'], '$height');
      expect(_drawn(tester).image!.width, width);
      expect(_drawn(tester).image!.height, height);

      await images.letTimersEnd(tester);
    },
  );

  testSession('a wide thumbnail covers its square at its own shape', (
    tester,
    session,
  ) async {
    const path = '/external/wide/thumbnail.png';
    final address = images.serve(path, images.largePhoto);

    await session.dispatch(
      'MESSAGE_CREATE',
      _messageWithEmbed({
        'thumbnail': _media(address, width: 1600, height: 800),
      }),
    );
    await images.waitUntil(
      tester,
      () => _drawn(tester).image != null,
      'the thumbnail',
    );

    // The square is 80 wide. A 2:1 picture covers it at 160 by 80, so its
    // short side stays sharp.
    final scale = tester.view.devicePixelRatio;
    final query = images.requestsFor(path).single.queryParameters;
    expect(query['width'], '${(160 * scale).round()}');
    expect(query['height'], '${(80 * scale).round()}');

    await images.letTimersEnd(tester);
  });

  testSession('an embed icon is asked for at the size it is drawn', (
    tester,
    session,
  ) async {
    const path = '/external/author/icon.png';
    final address = images.serve(path, images.largePhoto);

    await session.dispatch(
      'MESSAGE_CREATE',
      _messageWithEmbed({
        'author': {
          'name': 'Some author',
          'icon_url': 'https://pictures.example/icon',
          'proxy_icon_url': address,
        },
      }),
    );
    final icon = find.byKey(const ValueKey('embed-icon'));
    await images.waitUntil(
      tester,
      () => _drawn(tester, icon).image != null,
      'the icon',
    );

    final side = (20 * tester.view.devicePixelRatio).round();
    final query = images.requestsFor(path).single.queryParameters;
    expect(query['width'], '$side');
    expect(query['height'], '$side');
    // The picture is 3:2, so it fits the square with a shorter height.
    expect(_drawn(tester, icon).image!.width, side);

    await images.letTimersEnd(tester);
  });

  testSession('an embed image is not fetched again after a restart', (
    tester,
    session,
  ) async {
    const path = '/external/restart/photo.png';
    final message = _messageWithEmbed({
      'image': _media(images.serve(path, images.largePhoto)),
    });
    session.transport.on(
      'GET',
      '/api/v9/channels/${SessionHarness.dmChannelId}/messages',
      (_) => jsonResponse([message]),
    );
    await session.dispatch('MESSAGE_CREATE', message);
    await images.waitUntil(
      tester,
      () => _drawn(tester).image != null,
      'the embed image',
    );
    expect(images.requestsFor(path), hasLength(1));

    // A quit also empties the pictures held in memory, so only the disk is
    // left to answer.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await session.relaunch(ready: SessionHarness.defaultReady());
    await images.waitUntil(
      tester,
      () => _drawn(tester).image != null,
      'the embed image after the restart',
    );

    expect(images.requestsFor(path), hasLength(1));

    await images.letTimersEnd(tester);
  }, onDisk: true);

  testSession('an animated embed image moves on to its next frame', (
    tester,
    session,
  ) async {
    const path = '/external/moving/picture.gif';
    final address = images.serve(path, ChatImageDisk.redThenBlueGif);

    await session.dispatch(
      'MESSAGE_CREATE',
      _messageWithEmbed({'image': _media(address, width: 300, height: 200)}),
    );
    await images.waitUntil(
      tester,
      () => _drawn(tester).image != null,
      'the first frame',
    );
    final first = _drawn(tester).image!;
    expect(await _firstPixel(tester, first), 0xff0000ff);

    await images.waitUntil(tester, () {
      final now = _drawn(tester).image;
      return now != null && !now.isCloneOf(first);
    }, 'the second frame');

    expect(await _firstPixel(tester, _drawn(tester).image!), 0x0000ffff);
    expect(
      images.requestsFor(path).single.queryParameters,
      isNot(contains('format')),
    );

    await images.letTimersEnd(tester);
  });

  // Every Discord media proxy serves a still frame for `format=png`, whatever
  // its host. The path names the original picture, so it is left alone.
  testSession(
    'a GIF kept still asks its proxy for the png frame of the same path',
    (tester, session) async {
      const path = '/external/still/picture.gif';
      final address = images.serve(path, ChatImageDisk.redThenBlueGif);

      await session.dispatch(
        'MESSAGE_CREATE',
        _messageWithEmbed({'image': _media(address, width: 300, height: 200)}),
      );
      // Wait for the drawn frame, not just the request. The cache starts its
      // save timer before it hands the file over, so only then can
      // letTimersEnd run that timer out.
      await images.waitUntil(
        tester,
        () => _drawn(tester).image != null,
        'the still frame',
      );

      expect(images.requestsFor(path).single.queryParameters['format'], 'png');

      await images.letTimersEnd(tester);
    },
    ready: SessionHarness.defaultReady()
      ..['user_settings_proto'] = _gifsKeptStill(),
  );

  testSession('an embed image that cannot load shows the broken image icon', (
    tester,
    session,
  ) async {
    const path = '/external/gone/photo.png';

    await session.dispatch(
      'MESSAGE_CREATE',
      _messageWithEmbed({'image': _media(images.addressOf(path))}),
    );
    await images.waitUntil(
      tester,
      () => findFlucordIcon(FlucordIcons.brokenImage).evaluate().isNotEmpty,
      'the broken image icon',
    );

    await images.letTimersEnd(tester);
  });

  group('an animated embed image', () {
    for (final (away, back, how) in [
      (
        (SessionHarness session) => session.blurWindow(),
        (SessionHarness session) => session.focusWindow(),
        'unfocused',
      ),
      (
        (SessionHarness session) => session.minimizeWindow(),
        (SessionHarness session) => session.restoreWindow(),
        'suspended',
      ),
    ]) {
      testSession('stops while the window is $how, and moves on after', (
        tester,
        session,
      ) async {
        final path = '/external/$how/picture.gif';
        final address = images.serve(path, ChatImageDisk.redThenBlueGif);
        await session.dispatch(
          'MESSAGE_CREATE',
          _messageWithEmbed({
            'image': _media(address, width: 300, height: 200),
          }),
        );
        await images.waitUntil(
          tester,
          () => _drawn(tester).image != null,
          'the first frame',
        );

        away(session);
        await session.settle();
        final held = _drawn(tester).image!;
        await _wait(tester, const Duration(milliseconds: 400));

        expect(_drawn(tester).image!.isCloneOf(held), isTrue);
        expect(tester.binding.hasScheduledFrame, isFalse);

        back(session);
        await images.waitUntil(
          tester,
          () => !_drawn(tester).image!.isCloneOf(held),
          'the next frame',
        );
        await images.letTimersEnd(tester);
      });
    }
  });
}

/// Lets [time] pass on both clocks, a frame at a time.
Future<void> _wait(WidgetTester tester, Duration time) async {
  const frame = Duration(milliseconds: 16);
  for (var passed = Duration.zero; passed < time; passed += frame) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(frame);
  }
}

/// Account settings that turn GIF autoplay off.
String _gifsKeptStill() => DiscordUserSettingsProto.encodeBase64(
  (ProtoMessage()..setMessage(
        PreloadedUserSettingsField.textAndImages,
        ProtoMessage()..setBoolWrapper(TextAndImagesField.gifAutoPlay, false),
      ))
      .encode(),
);

/// The colour of the top left pixel of [image], as RGBA.
Future<int?> _firstPixel(WidgetTester tester, ui.Image image) =>
    tester.runAsync(() async => (await image.toByteData())!.getUint32(0));
