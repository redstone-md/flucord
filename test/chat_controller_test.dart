import 'package:flucord/src/domain/scheduled_event_repository.dart';
import 'package:flucord/src/domain/age_verification.dart';
import 'package:flucord/src/domain/multi_factor_auth.dart';
import 'package:flucord/src/domain/auth_session.dart';
import 'package:flucord/src/domain/family_centre.dart';
import 'package:flucord/src/domain/account_standing.dart';
import 'package:flucord/src/domain/automod_rule.dart';
import 'dart:async';
import 'package:flucord/src/domain/conversation_summary.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/message_component.dart';
import 'package:flucord/src/domain/application_command.dart';
import 'package:flucord/src/domain/gif_picker.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flucord/src/domain/stage_channel.dart';
import 'package:flucord/src/domain/thread_membership.dart';
import 'package:flucord/src/domain/user_profile.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/guild_management_repository.dart';
import 'package:flucord/src/domain/moderation_repository.dart';
import 'package:flucord/src/domain/message_search_repository.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';

part 'chat_controller_event_repository.dart';

void main() {
  group('ChatController', () {
    test('loads workspace and appends a sent message', () async {
      final controller = ChatController(
        MockChatRepository(latency: Duration.zero),
      );

      await controller.load();
      final initialCount = controller.workspace!.messages.length;
      final sent = await controller.sendMessage(
        channelId: 'forge-general',
        body: '  Repository boundary holds.  ',
      );

      expect(controller.state, ChatLoadState.ready);
      expect(sent, isTrue);
      expect(controller.workspace!.messages, hasLength(initialCount + 1));
      expect(
        controller.workspace!.messages.last.body,
        'Repository boundary holds.',
      );
    });

    test('rejects empty content', () async {
      final controller = ChatController(
        MockChatRepository(latency: Duration.zero),
      );
      await controller.load();

      expect(
        await controller.sendMessage(channelId: 'forge-general', body: '   '),
        isFalse,
      );
    });

    test('sends replies and attachments, then edits and deletes', () async {
      final controller = ChatController(
        MockChatRepository(latency: Duration.zero),
      );
      await controller.load();

      final sent = await controller.sendMessage(
        channelId: 'forge-general',
        body: '',
        replyToMessageId: 'm4',
        attachments: const [
          PendingAttachment(name: 'proof.txt', path: r'C:\proof.txt', size: 12),
        ],
      );
      final message = controller.workspace!.messages.last;

      expect(sent, isTrue);
      expect(message.attachments.single.fileName, 'proof.txt');
      expect(message.reply?.messageId, 'm4');
      expect(await controller.editMessage(message, 'Edited body'), isTrue);
      expect(controller.workspace!.messages.last.body, 'Edited body');

      await controller.addReaction(message, '✓');
      await Future<void>.delayed(Duration.zero);
      final reacted = controller.workspace!.messages.last;
      expect(reacted.reactions.single.reactedByCurrentUser, isTrue);

      await controller.toggleReaction(reacted, reacted.reactions.single);
      await Future<void>.delayed(Duration.zero);
      expect(controller.workspace!.messages.last.reactions, isEmpty);

      await controller.deleteMessage(message);
      expect(
        controller.workspace!.messages.any((item) => item.id == message.id),
        isFalse,
      );
    });

    test('loads and toggles pinned messages', () async {
      final controller = ChatController(
        MockChatRepository(latency: Duration.zero),
      );
      addTearDown(controller.dispose);
      await controller.load();

      await controller.loadPinnedMessages('forge-general');
      final pinned = controller
          .pinnedMessages('forge-general')!
          .messages
          .single;
      expect(pinned.id, 'm4');

      await controller.togglePin(pinned);
      expect(controller.pinnedMessages('forge-general')!.messages, isEmpty);
      expect(
        controller.workspace!.messagesFor('forge-general').last.isPinned,
        isFalse,
      );
    });

    test('a created event appears without waiting for the dispatch', () async {
      final repository = _EventRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      final draft = GuildScheduledEventDraft(
        name: 'Forge night',
        startTime: DateTime.utc(2026, 8, 1, 18),
        endTime: DateTime.utc(2026, 8, 1, 20),
        entityType: GuildScheduledEventEntityType.external,
        location: 'The workshop',
      );

      final created = await controller.createScheduledEvent('forge', draft);

      expect(created?.name, 'Forge night');
      expect(repository.created.single.name, 'Forge night');
      // The whole object came back from the server, so showing it is repeating
      // Discord rather than guessing at it.
      expect(
        controller.scheduledEventsFor('forge').map((e) => e.id),
        contains('event-new'),
      );
    });

    test('an edit replaces the row it changed', () async {
      final repository = _EventRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      final event = GuildScheduledEvent(
        id: 'event-1',
        spaceId: 'forge',
        name: 'Forge night',
        scheduledStartTime: DateTime.utc(2026, 8),
        entityType: GuildScheduledEventEntityType.external,
        status: GuildScheduledEventStatus.scheduled,
      );
      final edit = GuildScheduledEventEdit()..name = 'Renamed';

      final updated = await controller.editScheduledEvent(event, edit);

      expect(updated?.name, 'Renamed');
      expect(repository.edited.single['name'], 'Renamed');
      expect(
        controller
            .scheduledEventsFor('forge')
            .firstWhere((item) => item.id == 'event-1')
            .name,
        'Renamed',
      );
    });

    test('a deleted event leaves the list', () async {
      final repository = _EventRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      final event = GuildScheduledEvent(
        id: 'event-1',
        spaceId: 'forge',
        name: 'Forge night',
        scheduledStartTime: DateTime.utc(2026, 8),
        entityType: GuildScheduledEventEntityType.external,
        status: GuildScheduledEventStatus.scheduled,
      );
      await controller.editScheduledEvent(
        event,
        GuildScheduledEventEdit()..name = 'Forge night',
      );

      expect(await controller.deleteScheduledEvent(event), isTrue);

      expect(repository.deleted, ['event-1']);
      expect(
        controller.scheduledEventsFor('forge').map((item) => item.id),
        isNot(contains('event-1')),
      );
    });

    test('a refused write changes nothing and is not an error', () async {
      final repository = _EventRepository()..acceptEventWrite = false;
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      final event = GuildScheduledEvent(
        id: 'event-1',
        spaceId: 'forge',
        name: 'Forge night',
        scheduledStartTime: DateTime.utc(2026, 8),
        entityType: GuildScheduledEventEntityType.external,
        status: GuildScheduledEventStatus.scheduled,
      );

      expect(
        await controller.editScheduledEvent(
          event,
          GuildScheduledEventEdit()..name = 'Renamed',
        ),
        isNull,
      );
      expect(await controller.deleteScheduledEvent(event), isFalse);
      expect(controller.scheduledEventsError('forge'), isNull);
    });

    test('a failed write is recorded against its own guild', () async {
      final repository = _EventRepository()..failNextEventWrite = true;
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      expect(
        await controller.createScheduledEvent(
          'forge',
          GuildScheduledEventDraft(
            name: 'Forge night',
            startTime: DateTime.utc(2026, 8, 1, 18),
            endTime: DateTime.utc(2026, 8, 1, 20),
            entityType: GuildScheduledEventEntityType.external,
            location: 'The workshop',
          ),
        ),
        isNull,
      );

      expect(controller.scheduledEventsError('forge'), isA<StateError>());
    });

    test('an event RSVP names the guild it belongs to', () async {
      final repository = _EventRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      final event = GuildScheduledEvent(
        id: 'event-1',
        spaceId: 'forge',
        name: 'Forge night',
        scheduledStartTime: DateTime.utc(2026, 8),
        entityType: GuildScheduledEventEntityType.external,
        status: GuildScheduledEventStatus.scheduled,
      );

      expect(
        await controller.setEventInterest(event, interested: true),
        isTrue,
      );

      expect(repository.rsvps.single, ('forge', 'event-1', true));
      expect(controller.scheduledEventsError('forge'), isNull);
    });

    test('an RSVP that failed is recorded against its own guild', () async {
      final repository = _EventRepository()..failNextRsvp = true;
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      final event = GuildScheduledEvent(
        id: 'event-1',
        spaceId: 'forge',
        name: 'Forge night',
        scheduledStartTime: DateTime.utc(2026, 8),
        entityType: GuildScheduledEventEntityType.external,
        status: GuildScheduledEventStatus.scheduled,
      );

      expect(
        await controller.setEventInterest(event, interested: false),
        isFalse,
      );

      expect(controller.scheduledEventsError('forge'), isA<StateError>());
    });

    test('an alert is resolved against the guild it sits in', () async {
      final repository = _EventRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.openChannel('forge-general');
      final message = controller.workspace!.messages.first;

      await controller.resolveAutoModAlert(
        message,
        AutoModAlertAction.deleteUserMessage,
      );

      final resolved = repository.resolvedAlert!;
      // The guild is looked up here rather than asked of the surface: the
      // route is a guild route and the caller only has the message.
      expect(resolved.guildId, isNotEmpty);
      expect(resolved.channelId, message.channelId);
      expect(resolved.messageId, message.id);
      expect(resolved.action, AutoModAlertAction.deleteUserMessage);
      expect(controller.error, isNull);
    });

    test('an alert in no known channel asks nothing', () async {
      final repository = _EventRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.resolveAutoModAlert(
        ChatMessage(
          id: 'alert-1',
          channelId: 'channel-nobody-has',
          authorId: 'automod',
          body: 'Blocked',
          sentAt: DateTime.now(),
          type: DiscordMessageType.autoModerationAction,
        ),
        AutoModAlertAction.setCompleted,
      );

      expect(repository.resolvedAlert, isNull);
      expect(controller.error, isNull);
    });

    test('tracks live unread, mentions, presence, and typing', () async {
      final repository = _EventRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.openChannel('forge-general');
      final incomingMessage = controller.incomingMessages.first;

      repository.emit(
        MessageUpsertedEvent(
          message: ChatMessage(
            id: 'incoming-1',
            channelId: 'forge-native',
            authorId: 'lena',
            body: 'Mention from another channel',
            sentAt: DateTime.now(),
          ),
          isNew: true,
          mentionsCurrentMember: true,
        ),
      );
      repository.emit(
        const PresenceChangedEvent(
          memberId: 'lena',
          presence: UserPresence(status: Presence.online),
        ),
      );
      repository.emit(
        const TypingStartedEvent(channelId: 'forge-general', memberId: 'lena'),
      );
      await Future<void>.delayed(Duration.zero);

      expect((await incomingMessage).message.id, 'incoming-1');

      final unread = controller.workspace!.channelById('forge-native');
      expect(unread.unread, isTrue);
      expect(unread.mentionCount, 1);
      expect(unread.firstUnreadMessageId, 'incoming-1');
      expect(
        controller.workspace!.memberById('lena').presence,
        Presence.online,
      );
      expect(controller.typingMembersFor('forge-general').single.id, 'lena');

      await controller.openChannel('forge-native');
      final read = controller.workspace!.channelById('forge-native');
      expect(read.unread, isFalse);
      expect(read.mentionCount, 0);
      expect(read.firstUnreadMessageId, 'incoming-1');
      expect(
        controller.workspace!
            .messagesFor('forge-native')
            .map((item) => item.id),
        contains('incoming-1'),
      );
      expect(
        controller.workspace!
            .messagesFor('forge-native')
            .singleWhere((message) => message.id == 'incoming-1')
            .mentionsCurrentMember,
        isTrue,
      );

      await controller.openChannel('forge-general');
      expect(
        controller.workspace!.channelById('forge-native').firstUnreadMessageId,
        isNull,
      );
    });

    test(
      'marks every active channel read and clears unread boundaries',
      () async {
        final repository = _EventRepository();
        final controller = ChatController(repository);
        addTearDown(controller.dispose);
        await controller.load();

        repository.emit(
          MessageUpsertedEvent(
            message: ChatMessage(
              id: 'mention-for-inbox',
              channelId: 'forge-native',
              authorId: 'lena',
              body: 'Mention retained after reading',
              sentAt: DateTime.now(),
            ),
            isNew: true,
            mentionsCurrentMember: true,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          controller.workspace!.channelById('forge-native').mentionCount,
          1,
        );

        controller.markAllChannelsRead();

        final channel = controller.workspace!.channelById('forge-native');
        expect(channel.unread, isFalse);
        expect(channel.mentionCount, 0);
        expect(channel.firstUnreadMessageId, isNull);
        expect(
          controller.workspace!.messages
              .singleWhere((message) => message.id == 'mention-for-inbox')
              .mentionsCurrentMember,
          isTrue,
        );
      },
    );

    test('marks the active channel unread while the app is inactive', () async {
      final repository = _EventRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.openChannel('forge-general');
      controller.setApplicationActive(false);

      repository.emit(
        MessageUpsertedEvent(
          message: ChatMessage(
            id: 'background-1',
            channelId: 'forge-general',
            authorId: 'lena',
            body: 'Arrived while unfocused',
            sentAt: DateTime.now(),
          ),
          isNew: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.workspace!.channelById('forge-general').unread, isTrue);
      expect(
        controller.workspace!.channelById('forge-general').firstUnreadMessageId,
        'background-1',
      );
      controller.setApplicationActive(true);
      expect(
        controller.workspace!.channelById('forge-general').unread,
        isFalse,
      );
      expect(
        controller.workspace!.channelById('forge-general').firstUnreadMessageId,
        'background-1',
      );
      controller.setApplicationActive(false);
      expect(
        controller.workspace!.channelById('forge-general').firstUnreadMessageId,
        isNull,
      );
    });

    test(
      'opens and selects a direct conversation through repository state',
      () async {
        final controller = ChatController(
          MockChatRepository(latency: Duration.zero),
        );
        addTearDown(controller.dispose);
        await controller.load();

        final channelId = await controller.openDirectConversation(
          '123456789012345678',
        );

        expect(channelId, 'dm-123456789012345678');
        expect(
          controller.workspace!.spaceById(CommunitySpace.directMessagesId).kind,
          SpaceKind.directMessages,
        );
        expect(
          controller.workspace!.channelById(channelId!).recipientId,
          isNotNull,
        );
      },
    );

    test(
      'accepts a live direct message space before its channel and message',
      () async {
        final repository = _EventRepository();
        final controller = ChatController(repository);
        addTearDown(controller.dispose);
        await controller.load();
        const recipient = Member(
          id: 'dm-user',
          displayName: 'Jack',
          initials: 'J',
          role: 'Direct message',
          presence: Presence.offline,
          colorValue: 0xff59636a,
        );
        const channel = ConversationChannel(
          id: 'dm-live',
          spaceId: CommunitySpace.directMessagesId,
          name: 'Jack',
          topic: 'Direct message with Jack',
          kind: ChannelKind.text,
          recipientId: 'dm-user',
        );

        repository.emit(
          const SpaceUpsertedEvent(CommunitySpace.directMessages()),
        );
        repository.emit(const MemberUpsertedEvent(recipient));
        repository.emit(const ChannelUpsertedEvent(channel));
        repository.emit(
          MessageUpsertedEvent(
            message: ChatMessage(
              id: 'dm-message',
              channelId: channel.id,
              authorId: recipient.id,
              body: 'Direct signal',
              sentAt: DateTime.now(),
            ),
            member: recipient,
            isNew: true,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(controller.workspace!.channelById(channel.id).unread, isTrue);
        expect(
          controller.workspace!.messagesFor(channel.id).single.body,
          'Direct signal',
        );
      },
    );

    test('applies live category updates and deletes', () async {
      final repository = _EventRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      const category = ChannelCategory(
        id: 'live-category',
        spaceId: 'forge',
        name: 'Operations',
        position: 2,
      );

      repository.emit(const CategoryUpsertedEvent(category));
      await Future<void>.delayed(Duration.zero);
      expect(controller.workspace!.categories, contains(category));

      repository.emit(CategoryDeletedEvent(category.id));
      await Future<void>.delayed(Duration.zero);
      expect(controller.workspace!.categories, isNot(contains(category)));
    });

    test('folds a roster page of members in with one pass', () async {
      final repository = _EventRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      final existing = controller.workspace!.members.first;
      final before = controller.workspace!.members.length;

      repository.emit(const MembersUpsertedEvent([]));
      repository.emit(
        MembersUpsertedEvent([
          existing.copyWith(role: 'Roster role', presence: Presence.online),
          const Member(
            id: '234567890123456789',
            displayName: 'Roster arrival',
            initials: 'RA',
            role: 'Member',
            presence: Presence.idle,
            colorValue: 0xff59636a,
            spaceIds: {'forge'},
          ),
        ]),
      );
      await Future<void>.delayed(Duration.zero);

      final members = controller.workspace!.members;
      expect(members, hasLength(before + 1));
      expect(controller.workspace!.memberById(existing.id).role, 'Roster role');
      expect(
        controller.workspace!.memberById('234567890123456789').presence,
        Presence.idle,
      );
    });

    test('replaces one guild emoji catalog from a live event', () async {
      final repository = _EventRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      repository.emit(
        const GuildEmojisReplacedEvent(
          spaceId: 'forge',
          emojis: [
            GuildEmoji(id: 'live-emoji', spaceId: 'forge', name: 'online'),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.workspace!.emojisFor('forge').single.id, 'live-emoji');
    });
  });
}
