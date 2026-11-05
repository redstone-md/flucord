import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/forum_post_tile.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/flucord_icon_finder.dart';

void main() {
  testWidgets('uses the first image attachment as the gallery preview', (
    tester,
  ) async {
    await _pumpTile(tester, workspace: _imageWorkspace, gallery: true);

    expect(
      find.byKey(const ValueKey('forum-post-media-post-1')),
      findsOneWidget,
    );
    // Decoded at the card's size and kept on disk, so focus coming back to
    // the window does not fetch the picture again.
    final image = tester.widget<Image>(find.byType(Image)).image;
    expect(image, isA<ResizeImage>());
    final source = (image as ResizeImage).imageProvider;
    expect(source, isA<CachedNetworkImageProvider>());
    expect(
      (source as CachedNetworkImageProvider).url,
      'https://cdn.discordapp.com/attachments/1/2/capture.png',
    );
    final shown = tester.getSize(find.byType(Image));
    expect(image.width, (shown.width * tester.view.devicePixelRatio).round());
    expect(find.text('Native capture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a stable file fallback in a compact gallery card', (
    tester,
  ) async {
    await _pumpTile(
      tester,
      workspace: _fileWorkspace,
      gallery: true,
      width: 260,
    );

    expect(find.text('report.pdf'), findsWidgets);
    expect(findFlucordIcon(FlucordIcons.file), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps list cards text-first with a thumbnail beside', (
    tester,
  ) async {
    await _pumpTile(tester, workspace: _imageWorkspace, gallery: false);

    final text = tester.getTopLeft(
      find.text('Capture from the native client.'),
    );
    final thumbnail = tester.getTopLeft(
      find.byKey(const ValueKey('forum-post-media-post-1')),
    );
    expect(thumbnail.dx, greaterThan(text.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a picture-only post shows no file name as its text', (
    tester,
  ) async {
    await _pumpTile(
      tester,
      workspace: _workspace(_capture, body: ''),
      gallery: true,
      post: _countedPost,
    );

    expect(find.text('capture.png'), findsNothing);
    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('requests one lazy preview for a visible empty post', (
    tester,
  ) async {
    var requests = 0;
    await _pumpTile(
      tester,
      workspace: _emptyWorkspace,
      gallery: true,
      onLoadPreview: () => requests++,
    );
    await tester.pump();

    expect(requests, 1);
    await tester.pump();
    expect(requests, 1);
  });
}

Future<void> _pumpTile(
  WidgetTester tester, {
  required ChatWorkspace workspace,
  required bool gallery,
  double width = 520,
  ConversationChannel post = _post,
  VoidCallback? onLoadPreview,
}) => tester.pumpWidget(
  MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: gallery ? 260 : 128,
          child: ForumPostTile(
            workspace: workspace,
            parent: _media,
            post: post,
            gallery: gallery,
            onPressed: () {},
            onLoadPreview: onLoadPreview ?? () {},
          ),
        ),
      ),
    ),
  ),
);

const _media = ConversationChannel(
  id: 'media-1',
  spaceId: 'guild-1',
  name: 'captures',
  topic: '',
  kind: ChannelKind.media,
  availableTags: [ForumTag(id: 'tag-1', name: 'Native', moderated: false)],
  defaultForumLayout: ForumLayout.galleryView,
);

const _post = ConversationChannel(
  id: 'post-1',
  spaceId: 'guild-1',
  name: 'Native capture',
  topic: '',
  kind: ChannelKind.text,
  parentId: 'media-1',
  isThread: true,
  appliedTagIds: ['tag-1'],
);

const _countedPost = ConversationChannel(
  id: 'post-1',
  spaceId: 'guild-1',
  name: 'Native capture',
  topic: '',
  kind: ChannelKind.text,
  parentId: 'media-1',
  isThread: true,
  messageCount: 12,
);

const _capture = MessageAttachment(
  id: 'image-1',
  fileName: 'capture.png',
  url: 'https://cdn.discordapp.com/attachments/1/2/capture.png',
  size: 1024,
  contentType: 'image/png',
  width: 1280,
  height: 720,
);

final _imageWorkspace = _workspace(_capture);

final _fileWorkspace = _workspace(
  const MessageAttachment(
    id: 'file-1',
    fileName: 'report.pdf',
    url: 'https://cdn.discordapp.com/attachments/1/2/report.pdf',
    size: 1024,
    contentType: 'application/pdf',
  ),
  body: '',
);

final _emptyWorkspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [_media, _post],
  members: const [],
  messages: const [],
  currentMemberId: 'bot-1',
);

ChatWorkspace _workspace(MessageAttachment attachment, {String? body}) =>
    ChatWorkspace(
      spaces: const [
        CommunitySpace(
          id: 'guild-1',
          name: 'Forge',
          monogram: 'FO',
          colorValue: 0xff456b5a,
        ),
      ],
      channels: const [_media, _post],
      members: const [],
      messages: [
        ChatMessage(
          id: 'starter-1',
          channelId: 'post-1',
          authorId: 'bot-1',
          body: body ?? 'Capture from the native client.',
          sentAt: DateTime.utc(2026, 7, 23),
          attachments: [attachment],
        ),
      ],
      currentMemberId: 'bot-1',
    );
