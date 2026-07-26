import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/message_forward_destination_catalog.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/domain/message_embed.dart';
import 'package:flucord/src/presentation/widgets/forwarded_message_view.dart';
import 'package:flucord/src/presentation/widgets/message_forward_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  test(
    'catalog keeps every writable timeline and unlocked archived threads',
    () {
      final destinations = MessageForwardDestinationCatalog.fromWorkspace(
        _workspace,
      ).destinations;
      final ids = destinations.map((destination) => destination.channelId);

      expect(
        ids,
        containsAll([
          'source-channel',
          'target-channel',
          'voice',
          'open-thread',
        ]),
      );
      expect(ids, isNot(contains('forum')));
      expect(ids, isNot(contains('locked-thread')));
      final voice = destinations.firstWhere(
        (destination) => destination.channelId == 'voice',
      );
      expect(voice.kind, MessageForwardDestinationKind.voiceChannel);
      expect(voice.title, 'Voice');
    },
  );

  testWidgets('renders the complete forwarded snapshot on compact width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? selectedChannel;

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: ForwardedMessageView(
                snapshot: _snapshot,
                reference: const MessageReference(
                  type: DiscordMessageReferenceType.forward,
                  channelId: 'source-channel',
                  guildId: 'guild-1',
                ),
                workspace: _workspace,
                linkLauncher: const _TestLinkLauncher(),
                onSelectChannel: (id) => selectedChannel = id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Snapshot body'), findsOneWidget);
    expect(find.text('release.txt'), findsOneWidget);
    expect(find.text('Release ready'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('message-sticker-sticker-1')),
      findsOneWidget,
    );
    expect(find.textContaining('#general'), findsOneWidget);
    expect(find.textContaining('Forge'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('forwarded-components-unavailable')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('forwarded-message-source')));
    expect(selectedChannel, 'source-channel');
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters destinations and exposes loading and error states', (
    tester,
  ) async {
    final completion = Completer<bool>();
    await tester.pumpWidget(
      _DialogLauncher(onForward: (_, _) => completion.future),
    );
    await tester.tap(find.byKey(const ValueKey('open-forward-dialog')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-forward-voice')), findsOneWidget);
    expect(find.byKey(const ValueKey('message-forward-forum')), findsNothing);
    expect(
      find.byKey(const ValueKey('message-forward-locked-thread')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('message-forward-search')),
      'native',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('message-forward-target-channel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('message-forward-source-channel')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('message-forward-target-channel')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('message-forward-submit')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completion.complete(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-forward-error')), findsOneWidget);
    expect(find.textContaining('could not be forwarded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closes after a successful destination selection', (
    tester,
  ) async {
    String? destination;
    await tester.pumpWidget(
      _DialogLauncher(
        onForward: (_, channelId) async {
          destination = channelId;
          return true;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-forward-dialog')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('message-forward-target-channel')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('message-forward-submit')));
    await tester.pumpAndSettle();

    expect(destination, 'target-channel');
    expect(find.byKey(const ValueKey('message-forward-dialog')), findsNothing);
  });
}

class _DialogLauncher extends StatelessWidget {
  const _DialogLauncher({required this.onForward});

  final ForwardMessageCallback onForward;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: FlucordTheme.dark,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const ValueKey('open-forward-dialog'),
            onPressed: () => unawaited(
              MessageForwardDialog.show(
                context,
                message: _sourceMessage,
                workspace: _workspace,
                onForward: onForward,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

final _snapshot = MessageSnapshot(
  type: DiscordMessageType.defaultMessage,
  body: 'Snapshot body',
  sentAt: DateTime.utc(2026, 7, 24),
  attachments: const [
    MessageAttachment(
      id: 'attachment-1',
      fileName: 'release.txt',
      url: 'https://invalid.example/release.txt',
      size: 128,
    ),
  ],
  embeds: [MessageEmbed(type: 'rich', title: 'Release ready')],
  stickers: const [
    MessageSticker(
      id: 'sticker-1',
      name: 'Ship',
      format: StickerFormat.png,
      url: 'https://invalid.example/ship.png',
    ),
  ],
  components: const [MessageComponentSnapshot('{"type":1}')],
);

final _sourceMessage = ChatMessage(
  id: 'source-message',
  channelId: 'source-channel',
  authorId: 'member-1',
  body: 'Source body',
  sentAt: DateTime.utc(2026, 7, 24),
);

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'source-channel',
      spaceId: 'guild-1',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
    ),
    ConversationChannel(
      id: 'target-channel',
      spaceId: 'guild-1',
      name: 'native',
      topic: '',
      kind: ChannelKind.text,
    ),
    ConversationChannel(
      id: 'voice',
      spaceId: 'guild-1',
      name: 'Voice',
      topic: '',
      kind: ChannelKind.voice,
    ),
    ConversationChannel(
      id: 'forum',
      spaceId: 'guild-1',
      name: 'Forum',
      topic: '',
      kind: ChannelKind.forum,
    ),
    ConversationChannel(
      id: 'open-thread',
      spaceId: 'guild-1',
      name: 'Open archive',
      topic: '',
      kind: ChannelKind.text,
      isThread: true,
      isArchived: true,
    ),
    ConversationChannel(
      id: 'locked-thread',
      spaceId: 'guild-1',
      name: 'Locked',
      topic: '',
      kind: ChannelKind.text,
      isThread: true,
      isArchived: true,
      isLocked: true,
    ),
  ],
  members: const [
    Member(
      id: 'member-1',
      displayName: 'Jack',
      initials: 'JK',
      role: 'Member',
      presence: Presence.online,
      colorValue: 0xff456b5a,
    ),
  ],
  messages: [_sourceMessage],
  currentMemberId: 'member-1',
);

final class _TestLinkLauncher implements ExternalLinkLauncher {
  const _TestLinkLauncher();

  @override
  Future<bool> open(Uri uri) async => true;
}
