import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/quick_switcher_catalog.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  late QuickSwitcherCatalog catalog;

  setUp(() {
    catalog = QuickSwitcherCatalog.fromWorkspace(
      ChatWorkspace(
        spaces: const [
          CommunitySpace(
            id: 'guild',
            name: 'The Forge',
            monogram: 'TF',
            colorValue: 0xff5865f2,
          ),
          CommunitySpace.directMessages(),
        ],
        channels: const [
          ConversationChannel(
            id: 'general',
            spaceId: 'guild',
            name: 'general',
            topic: '',
            kind: ChannelKind.text,
            unread: true,
            mentionCount: 2,
          ),
          ConversationChannel(
            id: 'voice',
            spaceId: 'guild',
            name: 'Workshop',
            topic: '',
            kind: ChannelKind.voice,
          ),
          ConversationChannel(
            id: 'thread',
            spaceId: 'guild',
            name: 'release-checklist',
            topic: '',
            kind: ChannelKind.text,
            isThread: true,
          ),
          ConversationChannel(
            id: 'archived-thread',
            spaceId: 'guild',
            name: 'old-release',
            topic: '',
            kind: ChannelKind.text,
            isThread: true,
            isArchived: true,
          ),
          ConversationChannel(
            id: 'dm',
            spaceId: CommunitySpace.directMessagesId,
            name: 'User mira',
            topic: '',
            kind: ChannelKind.text,
            recipientId: 'mira',
            unread: true,
          ),
        ],
        members: const [
          Member(
            id: 'bot',
            displayName: 'Flucord',
            initials: 'F',
            role: 'Bot',
            presence: Presence.online,
            colorValue: 0xff5865f2,
          ),
          Member(
            id: 'mira',
            displayName: 'Mira Vale',
            initials: 'MV',
            role: 'Member',
            presence: Presence.online,
            colorValue: 0xff23a55a,
          ),
        ],
        messages: const [],
        currentMemberId: 'bot',
      ),
    );
  });

  test('projects grouped destinations with exact paths and activity', () {
    expect(catalog.destinations.map((destination) => destination.kind), const [
      QuickSwitcherDestinationKind.guild,
      QuickSwitcherDestinationKind.directMessage,
      QuickSwitcherDestinationKind.textChannel,
      QuickSwitcherDestinationKind.voiceChannel,
      QuickSwitcherDestinationKind.thread,
    ]);

    final guild = catalog.destinations.first;
    expect(guild.path, 'The Forge');
    expect(guild.unread, isTrue);
    expect(guild.mentionCount, 2);

    final dm = catalog.destinations[1];
    expect(dm.path, 'Direct Messages / @Mira Vale');
    expect(dm.unread, isTrue);

    final channel = catalog.destinations[2];
    expect(channel.path, 'The Forge / #general');
    expect(channel.mentionCount, 2);

    final thread = catalog.destinations.last;
    expect(thread.path, 'The Forge / #release-checklist');
    expect(
      catalog.destinations.map((destination) => destination.channelId),
      isNot(contains('archived-thread')),
    );
  });

  test('filters case-insensitively across every term in the full path', () {
    expect(catalog.search('forge GENERAL').single.channelId, 'general');
    expect(catalog.search('mira').single.channelId, 'dm');
    expect(catalog.search('missing'), isEmpty);
    expect(catalog.search('  '), hasLength(5));
  });
}
