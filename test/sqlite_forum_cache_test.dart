import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('persists forum metadata and applied post tags', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    await cache.writeWorkspace(_workspace);

    final restored = await cache.readWorkspace();
    final forum = restored!.channelById('forum-1');
    final post = restored.channelById('post-1');

    expect(forum.kind, ChannelKind.forum);
    expect(forum.availableTags.single.name, 'Client');
    expect(forum.availableTags.single.emojiName, 'C');
    expect(forum.defaultAutoArchiveDurationMinutes, 4320);
    expect(forum.defaultSortOrder, ForumSortOrder.creationDate);
    expect(forum.defaultForumLayout, ForumLayout.galleryView);
    expect(post.appliedTagIds, ['tag-1']);
  });
}

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
      id: 'forum-1',
      spaceId: 'guild-1',
      name: 'field-reports',
      topic: 'Post reports here',
      kind: ChannelKind.forum,
      availableTags: [
        ForumTag(id: 'tag-1', name: 'Client', moderated: false, emojiName: 'C'),
      ],
      defaultAutoArchiveDurationMinutes: 4320,
      defaultSortOrder: ForumSortOrder.creationDate,
      defaultForumLayout: ForumLayout.galleryView,
    ),
    ConversationChannel(
      id: 'post-1',
      spaceId: 'guild-1',
      name: 'native-cache',
      topic: '',
      kind: ChannelKind.text,
      parentId: 'forum-1',
      isThread: true,
      appliedTagIds: ['tag-1'],
    ),
  ],
  members: const [],
  messages: const [],
  currentMemberId: 'bot-1',
);
