import 'dart:async';

import 'package:flucord/src/presentation/widgets/pictures_ready.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A picture that loads when the test says so.
final class _HeldPicture extends ImageProvider<_HeldPicture> {
  final _done = Completer<ImageInfo>();

  Future<void> load(WidgetTester tester) async {
    final image = await tester.runAsync(() => createTestImage());
    _done.complete(ImageInfo(image: image!));
  }

  void fail() => _done.completeError(StateError('404'));

  @override
  Future<_HeldPicture> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_HeldPicture key, ImageDecoderCallback _) =>
      OneFrameImageStreamCompleter(_done.future);
}

final _shown = find.byKey(const ValueKey('shown'));

/// The frame that hears a picture has loaded, and the one that builds.
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _pump(WidgetTester tester, List<ImageProvider> pictures) =>
    tester.pumpWidget(
      PicturesReady(
        pictures: pictures,
        child: const SizedBox(key: ValueKey('shown')),
      ),
    );

void main() {
  testWidgets('shows nothing until every picture has loaded', (tester) async {
    final top = _HeldPicture();
    final bottom = _HeldPicture();
    await _pump(tester, [top, bottom]);

    await top.load(tester);
    await _frames(tester);
    expect(_shown, findsNothing);

    await bottom.load(tester);
    await _frames(tester);
    expect(_shown, findsOneWidget);
  });

  testWidgets('a picture that fails counts as done', (tester) async {
    final top = _HeldPicture();
    final bottom = _HeldPicture();
    await _pump(tester, [top, bottom]);

    await top.load(tester);
    bottom.fail();
    await _frames(tester);

    expect(_shown, findsOneWidget);
  });
}
