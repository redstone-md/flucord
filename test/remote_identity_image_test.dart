import 'package:flucord/src/presentation/widgets/remote_identity_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One transparent pixel, as the profile picker stages a picked image.
const _stagedPixel =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAA'
    'DUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

void main() {
  testWidgets('a staged data image is drawn, not swapped for the fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.square(
          dimension: 32,
          child: RemoteIdentityImage(
            url: _stagedPixel,
            fallback: SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final element = tester.element(find.byType(Image));
      final image = tester.widget<Image>(find.byType(Image)).image;
      await precacheImage(image, element);
    });
    await tester.pump();

    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
  });
}
