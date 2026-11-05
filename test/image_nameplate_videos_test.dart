import 'package:flucord/src/presentation/widgets/image_nameplate_videos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://cdn.example/nameplates/twilight/img.png';

void main() {
  setUp(() => PaintingBinding.instance.imageCache.clear());

  testWidgets('a nameplate decoded once starts at once on the next hover', (
    tester,
  ) async {
    final image = await tester.runAsync(() => createTestImage(width: 16));
    var loads = 0;
    PaintingBinding.instance.imageCache.putIfAbsent(
      const NetworkImage(_url),
      () {
        loads++;
        return OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image!.clone())),
        );
      },
    );
    const videos = ImageNameplateVideos();

    final first = videos.open(_url);
    await first.firstFrame;
    await first.dispose();
    final second = videos.open(_url);
    await second.firstFrame;
    await second.dispose();

    expect(loads, 1);
  });

  testWidgets('a nameplate that cannot load fails its first frame', (
    tester,
  ) async {
    final video = const ImageNameplateVideos().open(_url);
    Object? failure;

    await tester.runAsync(
      () => video.firstFrame.catchError((Object error) => failure = error),
    );

    expect(failure, isNotNull);
    await video.dispose();
  });
}
