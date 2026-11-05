import 'package:flucord/src/data/profile_asset_cache.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_image_disk.dart';

void main() {
  final disk = ChatImageDisk.declare();
  // Made outside a test, for the reason ChatImageDisk makes its own there.
  setUpAll(() => ProfileAssetCache.instance);

  testWidgets('a frame picture fetched once is drawn from the disk after', (
    tester,
  ) async {
    final url = disk.serve('/frame/top', disk.largePhoto);
    Future<void> draw() async {
      final loaded = UniqueKey();
      await tester.pumpWidget(
        Image(
          image: ProfileAssetCache.image(url),
          frameBuilder: (_, picture, frame, _) => frame == null
              ? picture
              : KeyedSubtree(key: loaded, child: picture),
        ),
      );
      await disk.waitUntil(
        tester,
        () => find.byKey(loaded).evaluate().isNotEmpty,
        'the picture',
      );
    }

    await draw();
    // As after a restart: nothing of it is left in memory, and no Image
    // still holds the picture it drew.
    await tester.pumpWidget(const SizedBox());
    imageCache
      ..clear()
      ..clearLiveImages();
    await draw();

    expect(disk.requestsFor('/frame/top'), hasLength(1));
    await disk.letTimersEnd(tester);
  });
}
