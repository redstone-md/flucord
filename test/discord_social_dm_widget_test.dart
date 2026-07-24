import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_friends_controller.dart';
import 'package:flucord/src/application/discord_social_dm_controller.dart';
import 'package:flucord/src/application/discord_social_dm_navigation_controller.dart';
import 'package:flucord/src/application/discord_social_sdk_controller.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_dm.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';
import 'package:flucord/src/presentation/widgets/discord_friends_scope.dart';
import 'package:flucord/src/presentation/widgets/discord_social_dm_navigation_scope.dart';
import 'package:flucord/src/presentation/widgets/discord_social_dm_scope.dart';
import 'package:flucord/src/presentation/widgets/discord_social_sdk_scope.dart';
import 'package:flucord/src/presentation/widgets/oauth_account_home.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('opens sidebar history and sends from the native composer', (
    tester,
  ) async {
    final harness = await _DmHarness.create();
    addTearDown(harness.dispose);
    await _pumpWorkspace(tester, harness);

    expect(
      find.byKey(const ValueKey('social-dm-conversation-friend-1')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('social-dm-conversation-friend-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('social-dm-view-friend-1')),
      findsOneWidget,
    );
    expect(find.text('first message'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('social-dm-composer')),
      'native reply',
    );
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('social-dm-send')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('social-dm-send')));
    await tester.pumpAndSettle();

    expect(harness.gateway.sent.single.content, 'native reply');
    expect(find.text('native reply'), findsOneWidget);
  });

  testWidgets('opens a direct message from a native friend row', (
    tester,
  ) async {
    final harness = await _DmHarness.create();
    addTearDown(harness.dispose);
    await _pumpWorkspace(tester, harness);

    await tester.tap(
      find.byKey(const ValueKey('discord-friend-message-friend-1')),
    );
    await tester.pumpAndSettle();

    expect(harness.navigation.selectedUserId, 'friend-1');
    expect(
      find.byKey(const ValueKey('social-dm-view-friend-1')),
      findsOneWidget,
    );
  });

  testWidgets('edits and confirms deletion from native message actions', (
    tester,
  ) async {
    final harness = await _DmHarness.create();
    addTearDown(harness.dispose);
    await _pumpWorkspace(tester, harness);
    await tester.tap(
      find.byKey(const ValueKey('social-dm-conversation-friend-1')),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('social-dm-message-message-2'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(row));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('social-dm-edit-message-2')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('social-dm-edit-field-message-2')),
      'edited message',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('edited message'), findsOneWidget);
    expect(harness.gateway.edited.single.messageId, 'message-2');

    await mouse.moveTo(tester.getCenter(row));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('social-dm-delete-message-2')));
    await tester.pumpAndSettle();
    expect(find.text('Delete message?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('social-dm-confirm-delete-message-2')),
    );
    await tester.pumpAndSettle();

    expect(row, findsNothing);
    expect(harness.gateway.deleted.single.messageId, 'message-2');
    await mouse.removePointer();
  });

  testWidgets('coordinates Discord notification suppression with lifecycle', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final harness = await _DmHarness.create();
    addTearDown(harness.dispose);
    await _pumpWorkspace(tester, harness);
    await tester.tap(
      find.byKey(const ValueKey('social-dm-conversation-friend-1')),
    );
    await tester.pumpAndSettle();
    expect(harness.gateway.showingChat, [true]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    harness.navigation.showFriends();
    await tester.pump();

    expect(harness.gateway.showingChat, [true, false, true, false]);
  });
}

Future<void> _pumpWorkspace(WidgetTester tester, _DmHarness harness) async {
  await tester.binding.setSurfaceSize(const Size(900, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final account = DiscordOAuthAccount(
    id: 'current',
    username: 'jack',
    displayName: 'Jack',
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: DiscordSocialSdkScope(
        controller: harness.social,
        child: DiscordSocialDmNavigationScope(
          controller: harness.navigation,
          child: DiscordSocialDmScope(
            controller: harness.dms,
            child: DiscordFriendsScope(
              controller: harness.friends,
              child: Scaffold(
                body: Row(
                  children: [
                    OAuthAccountSidebar(account: account),
                    Expanded(child: OAuthAccountHomeView(account: account)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _DmHarness {
  const _DmHarness({
    required this.gateway,
    required this.social,
    required this.friends,
    required this.dms,
    required this.navigation,
  });

  final _SocialDmGateway gateway;
  final DiscordSocialSdkController social;
  final DiscordFriendsController friends;
  final DiscordSocialDmController dms;
  final DiscordSocialDmNavigationController navigation;

  static Future<_DmHarness> create() async {
    final gateway = _SocialDmGateway();
    final social = DiscordSocialSdkController(gateway);
    final friends = DiscordFriendsController(gateway);
    final dms = DiscordSocialDmController(gateway);
    final navigation = DiscordSocialDmNavigationController();
    void reconcile() {
      friends.reconcileSession(
        social.availability,
        authenticated: social.isAuthenticated,
      );
      dms.reconcileSession(
        social.availability,
        authenticated: social.isAuthenticated,
      );
    }

    social.addListener(reconcile);
    await social.initialize();
    await friends.initialize();
    await dms.initialize();
    return _DmHarness(
      gateway: gateway,
      social: social,
      friends: friends,
      dms: dms,
      navigation: navigation,
    );
  }

  Future<void> dispose() async {
    social.dispose();
    friends.dispose();
    dms.dispose();
    navigation.dispose();
    await gateway.dispose();
  }
}

final class _SocialDmGateway
    implements
        DiscordSocialSdkGateway,
        DiscordSocialDmGateway,
        DiscordSocialDmEvents {
  final StreamController<DiscordSocialDmEvent> _events =
      StreamController.broadcast(sync: true);
  final List<({String userId, String content})> sent = [];
  final List<({String userId, String messageId, String content})> edited = [];
  final List<({String userId, String messageId})> deleted = [];
  final List<bool> showingChat = [];
  final Map<String, List<DiscordSocialDmMessage>> _messages = {
    'friend-1': [
      DiscordSocialDmMessage(
        id: 'message-1',
        conversationUserId: 'friend-1',
        authorId: 'friend-1',
        recipientId: 'current',
        authorDisplayName: 'Ada',
        content: 'first message',
        sentAt: DateTime.utc(2026, 2, 22),
        authoredByCurrentUser: false,
      ),
      DiscordSocialDmMessage(
        id: 'message-2',
        conversationUserId: 'friend-1',
        authorId: 'current',
        recipientId: 'friend-1',
        authorDisplayName: 'Jack',
        content: 'my message',
        sentAt: DateTime.utc(2026, 2, 22, 0, 1),
        authoredByCurrentUser: true,
      ),
    ],
  };

  @override
  Stream<DiscordSocialDmEvent> get socialDmEvents => _events.stream;

  @override
  Future<DiscordSocialSdkAuthentication> authorize() async =>
      DiscordSocialSdkAuthentication.ready;

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      DiscordSocialSdkAvailability.ready;

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<DiscordSocialDmConversation>> fetchConversations() async => [
    DiscordSocialDmConversation(
      user: _friend.user,
      lastMessageId: _messages['friend-1']!.last.id.replaceAll('message-', ''),
    ),
  ];

  @override
  Future<List<DiscordSocialDmMessage>> fetchMessages({
    required String userId,
    int limit = 100,
  }) async => _messages[userId] ?? const [];

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async => [_friend];

  @override
  Future<DiscordSocialSdkAuthentication> restoreAuthentication() async =>
      DiscordSocialSdkAuthentication.ready;

  @override
  Future<String> sendMessage({
    required String userId,
    required String content,
  }) async {
    sent.add((userId: userId, content: content));
    final message = DiscordSocialDmMessage(
      id: 'message-3',
      conversationUserId: userId,
      authorId: 'current',
      recipientId: userId,
      authorDisplayName: 'Jack',
      content: content,
      sentAt: DateTime.utc(2026, 2, 22, 0, 1),
      authoredByCurrentUser: true,
    );
    _messages[userId] = [..._messages[userId] ?? const [], message];
    return message.id;
  }

  @override
  Future<void> editMessage({
    required String userId,
    required String messageId,
    required String content,
  }) async {
    edited.add((userId: userId, messageId: messageId, content: content));
    _messages[userId] = [
      for (final message in _messages[userId] ?? const [])
        if (message.id == messageId)
          DiscordSocialDmMessage(
            id: message.id,
            conversationUserId: message.conversationUserId,
            authorId: message.authorId,
            recipientId: message.recipientId,
            authorDisplayName: message.authorDisplayName,
            content: content,
            sentAt: message.sentAt,
            editedAt: DateTime.utc(2026, 2, 22, 0, 2),
            authoredByCurrentUser: message.authoredByCurrentUser,
          )
        else
          message,
    ];
  }

  @override
  Future<void> deleteMessage({
    required String userId,
    required String messageId,
  }) async {
    deleted.add((userId: userId, messageId: messageId));
    _messages[userId] = List.of(
      (_messages[userId] ?? const []).where(
        (message) => message.id != messageId,
      ),
    );
  }

  @override
  Future<void> setShowingChat(bool showing) async {
    showingChat.add(showing);
  }

  @override
  Future<void> updateRelationship({
    required String userId,
    required DiscordRelationshipAction action,
  }) async {}

  Future<void> dispose() => _events.close();

  static final _friend = DiscordRelationship(
    user: DiscordRelationshipUser(
      id: 'friend-1',
      displayName: 'Ada',
      status: DiscordPresenceStatus.online,
    ),
    kind: DiscordRelationshipKind.friend,
  );
}
