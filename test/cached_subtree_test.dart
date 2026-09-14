import 'package:flucord/src/presentation/widgets/cached_subtree.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// [CachedSubtree] is what keeps a rebuilt shell from redrawing the parts of
/// itself nothing moved in, so what counts as "nothing moved" is worth pinning.
void main() {
  testWidgets('keeps the subtree while the dependencies match', (tester) async {
    var builds = 0;
    Future<void> pumpWith(List<Object?> dependencies) => tester.pumpWidget(
      CachedSubtree(
        dependencies: dependencies,
        builder: (_) {
          builds++;
          return const SizedBox();
        },
      ),
    );

    await pumpWith(['alpha', 1]);
    expect(builds, 1);

    await pumpWith(['alpha', 1]);
    expect(builds, 1);

    await pumpWith(['alpha', 2]);
    expect(builds, 2);
  });

  testWidgets('compares collections by their contents', (tester) async {
    var builds = 0;
    Future<void> pumpWith(List<Object?> dependencies) => tester.pumpWidget(
      CachedSubtree(
        dependencies: dependencies,
        builder: (_) {
          builds++;
          return const SizedBox();
        },
      ),
    );

    // A fresh list, set and map holding the same entries: the common case, as
    // the workspace hands out new collections while their entries stay put.
    await pumpWith([
      ['a', 'b'],
      {'a'},
      {'a': 1},
    ]);
    expect(builds, 1);

    await pumpWith([
      ['a', 'b'],
      {'a'},
      {'a': 1},
    ]);
    expect(builds, 1);

    await pumpWith([
      ['a', 'c'],
      {'a'},
      {'a': 1},
    ]);
    expect(builds, 2);

    await pumpWith([
      ['a', 'c'],
      {'a'},
      {'a': 2},
    ]);
    expect(builds, 3);
  });
}
