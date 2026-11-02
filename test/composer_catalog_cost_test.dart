import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/app_composition.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/build_counter.dart';
import 'support/pane_harness.dart';

/// A list that counts how many of its items were read. The workspace keeps a
/// list that is already sealed as it stands, so this one stays in place.
final class _CountedList<T> extends UnmodifiableListView<T> {
  _CountedList(super.source);

  int reads = 0;

  @override
  T operator [](int index) {
    reads++;
    return super[index];
  }
}

void main() {
  late AppComposition composition;
  late ChatWorkspace base;
  late _CountedList<GuildEmoji> emojis;

  Widget pane(ChatWorkspace workspace) => MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: paneHarness(
        composition,
        workspace,
        channel: workspace.channelById('forge-general'),
      ),
    ),
  );

  setUp(() async {
    composition = AppComposition(AppBootstrap.demo());
    addTearDown(composition.dispose);
    final seeded = await MockChatRepository(
      latency: Duration.zero,
    ).loadWorkspace();
    emojis = _CountedList([
      ...seeded.emojis,
      const GuildEmoji(id: 'party', spaceId: 'forge', name: 'party_parrot'),
    ]);
    base = seeded.copyWith(emojis: emojis);
    composition.workspace
      ..reconcile(base)
      ..selectChannel('forge-general');
  });

  testWidgets(
    'with the list closed, a pane rebuild does not build the catalog',
    (tester) async {
      await tester.pumpWidget(pane(base));
      await tester.pumpAndSettle();
      emojis.reads = 0;

      final builds = await countBuilds(
        () => tester.pumpWidget(pane(base.copyWith(messages: const []))),
      );

      expect(builds.of<MessageComposer>(), greaterThan(0));
      expect(emojis.reads, 0);
    },
  );

  testWidgets('typing a trigger builds the catalog', (tester) async {
    await tester.pumpWidget(pane(base));
    await tester.pumpAndSettle();
    emojis.reads = 0;

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      ':party',
    );
    await tester.pump();

    expect(emojis.reads, greaterThan(0));
    expect(
      find.byKey(const ValueKey('composer-suggestion-emoji-party')),
      findsOneWidget,
    );
  });

  test('emoji and stickers are grouped by space once per list', () {
    GuildSticker sticker(String id, String spaceId, {bool available = true}) =>
        GuildSticker(
          item: MessageSticker(
            id: id,
            name: id,
            format: StickerFormat.png,
            url: 'https://example.test/$id.png',
          ),
          spaceId: spaceId,
          tags: const [],
          available: available,
        );
    final countedStickers = _CountedList([
      sticker('wave', 'a'),
      sticker('gone', 'a', available: false),
      sticker('nod', 'b'),
    ]);
    final countedEmojis = _CountedList(const [
      GuildEmoji(id: 'one', spaceId: 'a', name: 'one'),
      GuildEmoji(id: 'off', spaceId: 'a', name: 'off', available: false),
      GuildEmoji(id: 'two', spaceId: 'b', name: 'two'),
    ]);
    final workspace = ChatWorkspace(
      spaces: const [],
      channels: const [],
      members: const [],
      messages: const [],
      emojis: countedEmojis,
      stickers: countedStickers,
      currentMemberId: 'me',
    );

    expect(workspace.emojisFor('a').map((emoji) => emoji.id), ['one']);
    expect(workspace.emojisFor('b').map((emoji) => emoji.id), ['two']);
    expect(workspace.emojisFor('none'), isEmpty);
    expect(workspace.stickersFor('a').map((item) => item.id), ['wave']);
    expect(workspace.stickersFor('b').map((item) => item.id), ['nod']);
    final emojiReads = countedEmojis.reads;
    final stickerReads = countedStickers.reads;

    // Another workspace over the same lists asks for the other space too.
    final next = workspace.copyWith(messages: const []);
    next.emojisFor('b');
    next.stickersFor('a');

    expect(countedEmojis.reads, emojiReads);
    expect(countedStickers.reads, stickerReads);
  });
}
