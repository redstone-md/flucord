import 'dart:async';

import 'package:flucord/src/data/discord/discord_cdn.dart';
import 'package:flucord/src/data/discord/display_name_fonts.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/member_sidebar.dart';
import 'package:flucord/src/presentation/widgets/name_style_scope.dart';
import 'package:flucord/src/presentation/widgets/nameplate_motion.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for media_kit, which cannot run under `flutter test`.
final class _FakeVideos implements NameplateVideos {
  final opened = <_FakeVideo>[];

  Iterable<_FakeVideo> get live => opened.where((video) => !video.disposed);

  @override
  NameplateVideo open(String url) {
    final video = _FakeVideo(url);
    opened.add(video);
    return video;
  }
}

final class _FakeVideo implements NameplateVideo {
  _FakeVideo(this.url);

  final String url;
  final _firstFrame = Completer<void>();
  bool disposed = false;

  void showFirstFrame() => _firstFrame.complete();

  @override
  Future<void> get firstFrame => _firstFrame.future;

  @override
  Widget view() => SizedBox.expand(key: ValueKey('moving $url'));

  @override
  Future<void> dispose() async => disposed = true;
}

Member _person(String id) => Member(
  id: id,
  displayName: id,
  initials: id[0].toUpperCase(),
  role: 'Member',
  presence: Presence.online,
  colorValue: 0xff59636a,
  spaceIds: const {'guild-1'},
  tags: MemberTags(nameplate: Nameplate(asset: 'nameplates/nameplates/$id/')),
);

String _moving(String id) =>
    DiscordCdn.movingNameplate('nameplates/nameplates/$id/')!;

/// Puts a decoded still picture in the image cache for [ids], as if it had
/// loaded from the CDN. The test binding answers every request with 400.
Future<void> _stillPicturesLoaded(WidgetTester tester, List<String> ids) async {
  final image = await tester.runAsync(() => createTestImage(width: 16));
  for (final id in ids) {
    final url = DiscordCdn.nameplate('nameplates/nameplates/$id/')!;
    PaintingBinding.instance.imageCache.putIfAbsent(
      NetworkImage(url),
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: image!.clone())),
      ),
    );
  }
}

Future<void> _pumpMembers(
  WidgetTester tester,
  _FakeVideos videos, {
  bool reducedMotion = false,
  ValueListenable<bool>? lookedAt,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      // As the app's motion rule does for an unfocused or suspended window.
      builder: (context, child) => ValueListenableBuilder(
        valueListenable: lookedAt ?? ValueNotifier(true),
        builder: (context, lookedAt, _) => TickerMode(
          enabled: lookedAt,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reducedMotion),
            child: child!,
          ),
        ),
      ),
      home: NameStyleScope(
        videos: videos,
        fonts: DisplayNameFonts(
          load: (font) => throw StateError('no font is loaded here'),
        ),
        child: Scaffold(
          body: Row(
            children: [
              const Expanded(child: SizedBox()),
              MemberSidebar(
                members: [_person('mira'), _person('jack')],
                spaceId: 'guild-1',
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _hover(TestGesture mouse, WidgetTester tester, String id) async {
  await mouse.moveTo(tester.getCenter(find.byKey(ValueKey('member-row-$id'))));
  await tester.pump();
}

/// Puts a still picture for [id] in the image cache that arrives only when
/// the returned callback is called.
Future<VoidCallback> _stillPictureLater(WidgetTester tester, String id) async {
  final image = await tester.runAsync(() => createTestImage(width: 16));
  final arrived = Completer<ImageInfo>();
  PaintingBinding.instance.imageCache.putIfAbsent(
    NetworkImage(DiscordCdn.nameplate('nameplates/nameplates/$id/')!),
    () => OneFrameImageStreamCompleter(arrived.future),
  );
  return () => arrived.complete(ImageInfo(image: image!.clone()));
}

Finder _stillOf(String id) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is NetworkImage &&
      (widget.image as NetworkImage).url ==
          DiscordCdn.nameplate('nameplates/nameplates/$id/'),
);

void main() {
  // The image cache outlives a test: each starts with no picture loaded.
  setUp(() => PaintingBinding.instance.imageCache.clear());

  testWidgets('hovering a row plays its moving nameplate over the still one', (
    tester,
  ) async {
    final videos = _FakeVideos();
    await _stillPicturesLoaded(tester, ['mira', 'jack']);
    await _pumpMembers(tester, videos);
    final mouse = await _mouse(tester);

    await _hover(mouse, tester, 'mira');

    expect(videos.live.map((video) => video.url), [_moving('mira')]);
    expect(
      find.byKey(ValueKey('moving ${_moving('mira')}')),
      findsNothing,
      reason: 'the still picture stays until the first frame shows',
    );

    videos.opened.single.showFirstFrame();
    await tester.pump();

    expect(find.byKey(ValueKey('moving ${_moving('mira')}')), findsOneWidget);
    expect(_stillOf('mira'), findsOneWidget, reason: 'it stays underneath');
  });

  testWidgets('only one nameplate moves at a time', (tester) async {
    final videos = _FakeVideos();
    await _stillPicturesLoaded(tester, ['mira', 'jack']);
    await _pumpMembers(tester, videos);
    final mouse = await _mouse(tester);

    await _hover(mouse, tester, 'mira');
    videos.opened.single.showFirstFrame();
    await tester.pump();
    await _hover(mouse, tester, 'jack');

    expect(videos.live.map((video) => video.url), [_moving('jack')]);
    expect(find.byKey(ValueKey('moving ${_moving('mira')}')), findsNothing);
  });

  testWidgets('leaving the row goes back to the still picture', (tester) async {
    final videos = _FakeVideos();
    await _stillPicturesLoaded(tester, ['mira', 'jack']);
    await _pumpMembers(tester, videos);
    final mouse = await _mouse(tester);

    await _hover(mouse, tester, 'mira');
    videos.opened.single.showFirstFrame();
    await tester.pump();
    await mouse.moveTo(Offset.zero);
    await tester.pump();

    expect(videos.live, isEmpty);
    expect(find.byKey(ValueKey('moving ${_moving('mira')}')), findsNothing);
    expect(_stillOf('mira'), findsOneWidget);
  });

  testWidgets('reduced motion keeps the nameplate still', (tester) async {
    final videos = _FakeVideos();
    await _stillPicturesLoaded(tester, ['mira', 'jack']);
    await _pumpMembers(tester, videos, reducedMotion: true);
    final mouse = await _mouse(tester);

    await _hover(mouse, tester, 'mira');

    expect(videos.opened, isEmpty);
  });

  testWidgets('a still picture that failed to load does not move', (
    tester,
  ) async {
    final videos = _FakeVideos();
    await _pumpMembers(tester, videos);
    await tester.pump();
    final mouse = await _mouse(tester);

    await _hover(mouse, tester, 'mira');

    expect(videos.opened, isEmpty);
  });

  testWidgets('a moving nameplate that fails stays still', (tester) async {
    final videos = _FakeVideos();
    await _stillPicturesLoaded(tester, ['mira', 'jack']);
    await _pumpMembers(tester, videos);
    final mouse = await _mouse(tester);

    await _hover(mouse, tester, 'mira');
    videos.opened.single._firstFrame.completeError(StateError('404'));
    await tester.pump();

    expect(videos.live, isEmpty);
    expect(_stillOf('mira'), findsOneWidget);
  });

  testWidgets('a hover that came before the still picture plays once it shows', (
    tester,
  ) async {
    final videos = _FakeVideos();
    final arrive = await _stillPictureLater(tester, 'mira');
    await _pumpMembers(tester, videos);
    final mouse = await _mouse(tester);
    await _hover(mouse, tester, 'mira');
    expect(videos.opened, isEmpty);

    arrive();
    await tester.pump();
    await tester.pump();

    expect(videos.live.single.url, _moving('mira'));
  });

  testWidgets('a nameplate stops while the window is not looked at', (
    tester,
  ) async {
    final videos = _FakeVideos();
    final lookedAt = ValueNotifier(true);
    addTearDown(lookedAt.dispose);
    await _stillPicturesLoaded(tester, ['mira', 'jack']);
    await _pumpMembers(tester, videos, lookedAt: lookedAt);
    final mouse = await _mouse(tester);
    await _hover(mouse, tester, 'mira');
    videos.live.single.showFirstFrame();
    await tester.pump();

    lookedAt.value = false;
    await tester.pump();
    expect(videos.live, isEmpty);
    expect(find.byKey(ValueKey('moving ${_moving('mira')}')), findsNothing);

    lookedAt.value = true;
    await tester.pump();
    expect(videos.live.single.url, _moving('mira'));
  });
}
