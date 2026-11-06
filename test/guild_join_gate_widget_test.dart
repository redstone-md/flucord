import 'dart:async';

import 'package:flucord/src/app.dart';
import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/account_entitlements.dart';
import 'package:flucord/src/domain/application_command.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/conversation_summary.dart';
import 'package:flucord/src/domain/desktop_relationship_repository.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/game_detection.dart';
import 'package:flucord/src/domain/gif_picker.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/guild_expression_repository.dart';
import 'package:flucord/src/domain/guild_join_gate.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/domain/guild_management_repository.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/domain/message_component.dart';
import 'package:flucord/src/domain/message_search_repository.dart';
import 'package:flucord/src/domain/moderation_repository.dart';
import 'package:flucord/src/domain/permission_overwrite.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flucord/src/domain/stage_channel.dart';
import 'package:flucord/src/domain/thread_membership.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _home = 'home-guild';
const _garden = 'garden-guild';
const _gardener = 'gardener-role';
const _me = 'member-1';

const _rules = RulesScreening(
  version: '2026-11-01T10:00:00.000000+00:00',
  fields: [
    RulesScreeningField(
      type: RulesScreeningField.rulesType,
      label: 'Read and agree to the server rules',
      required: true,
      rules: ['Be kind to every plant.', 'No spam.'],
    ),
  ],
);

const _onboarding = GuildOnboarding(
  guildId: _garden,
  prompts: [
    OnboardingPrompt(
      id: 'prompt-1',
      title: 'What brings you here?',
      singleSelect: true,
      required: true,
      options: [
        OnboardingOption(
          id: 'option-garden',
          title: 'Gardening',
          emoji: '🌱',
          roleIds: [_gardener],
          channelIds: ['greenhouse'],
        ),
        OnboardingOption(id: 'option-cook', title: 'Cooking'),
      ],
    ),
  ],
);

void main() {
  testWidgets('a pending member reads and accepts the rules, then can talk', (
    tester,
  ) async {
    final plane = _GatePlane();
    await _pumpShell(tester, plane, pendingAtHome: true);

    expect(find.byKey(const ValueKey('message-composer')), findsNothing);
    expect(find.byKey(const ValueKey('pending-member-notice')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pending-member-read-rules')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guild-rules-dialog')), findsOneWidget);
    expect(find.text('Be kind to every plant.'), findsOneWidget);
    expect(find.text('No spam.'), findsOneWidget);

    // The rules are agreed to on purpose, not by the button alone.
    await tester.tap(find.byKey(const ValueKey('guild-rules-submit')));
    await tester.pumpAndSettle();
    expect(plane.acceptedIn, isEmpty);

    await tester.tap(find.byKey(const ValueKey('guild-rules-agree')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('guild-rules-submit')));
    await tester.pumpAndSettle();

    expect(plane.acceptedIn, [_home]);
    expect(find.byKey(const ValueKey('guild-rules-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('pending-member-notice')), findsNothing);
    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('joining a server with onboarding walks its prompt, and the '
      'chosen channel shows', (tester) async {
    final plane = _GatePlane(onboarding: _onboarding);
    await _pumpShell(tester, plane);
    await _join(tester);

    expect(
      find.byKey(const ValueKey('guild-onboarding-dialog')),
      findsOneWidget,
    );
    expect(find.text('What brings you here?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-option-garden')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('guild-onboarding-next')));
    await tester.pumpAndSettle();

    expect(plane.answers, [
      {'option-garden'},
    ]);
    expect(find.byKey(const ValueKey('guild-onboarding-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('channel-greenhouse')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a server with neither is joined as before', (tester) async {
    final plane = _GatePlane();
    await _pumpShell(tester, plane);
    await _join(tester);

    expect(find.byKey(const ValueKey('guild-onboarding-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('guild-rules-dialog')), findsNothing);
    expect(
      find.byKey(const ValueKey('channel-garden-general')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('channel-greenhouse')), findsNothing);
    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(plane.answers, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpShell(
  WidgetTester tester,
  _GatePlane plane, {
  bool pendingAtHome = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    FlucordApp(
      bootstrap: AppBootstrap(
        initialRepository: _GateRepository(
          plane,
          _workspace(pendingAtHome: pendingAtHome),
        ),
        initialSessionMode: SessionMode.demo,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _join(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('add-server')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('add-server-join')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('join-server-invite-field')),
    'garden',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('join-server-submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('join-server-submit')));
  await tester.pumpAndSettle();
}

final _everyone = DiscordPermissions.combine([
  DiscordPermissions.viewChannel,
  DiscordPermissions.readMessageHistory,
  DiscordPermissions.sendMessages,
]);

CommunityRole _everyoneIn(String guildId) => CommunityRole(
  id: guildId,
  spaceId: guildId,
  name: '@everyone',
  position: 0,
  permissions: _everyone,
);

ConversationChannel _channel(
  String id,
  String guildId, {
  Map<String, DiscordPermissionOverwrite> overwrites = const {},
}) => ConversationChannel(
  id: id,
  spaceId: guildId,
  name: id,
  topic: '',
  kind: ChannelKind.text,
  position: 0,
  permissionOverwrites: overwrites,
);

Member _account(Map<String, GuildMembership> memberships) => Member(
  id: _me,
  displayName: 'Ada',
  initials: 'A',
  role: 'Member',
  presence: Presence.online,
  colorValue: 0xff456b5a,
  spaceIds: memberships.keys.toSet(),
  membershipsBySpace: memberships,
);

ChatWorkspace _workspace({required bool pendingAtHome}) => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: _home,
      name: 'Home',
      monogram: 'H',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: [_channel('home-general', _home)],
  roles: [_everyoneIn(_home)],
  members: [
    _account({_home: GuildMembership(isPending: pendingAtHome)}),
  ],
  messages: const [],
  currentMemberId: _me,
);

/// The garden server as a join hydrates it: a general channel, and a
/// greenhouse only the gardener role may see.
JoinedGuild _gardenGuild() => JoinedGuild(
  space: const CommunitySpace(
    id: _garden,
    name: 'Garden',
    monogram: 'G',
    colorValue: 0xff456b5a,
  ),
  channels: [
    _channel('garden-general', _garden),
    _channel(
      'greenhouse',
      _garden,
      overwrites: {
        _garden: DiscordPermissionOverwrite(
          id: _garden,
          allow: BigInt.zero,
          deny: DiscordPermissions.viewChannel,
        ),
        _gardener: DiscordPermissionOverwrite(
          id: _gardener,
          allow: DiscordPermissions.viewChannel,
          deny: BigInt.zero,
        ),
      },
    ),
  ],
  categories: const [],
  roles: [
    _everyoneIn(_garden),
    const CommunityRole(
      id: _gardener,
      spaceId: _garden,
      name: 'Gardener',
      position: 1,
    ),
  ],
  members: [
    _account({_garden: const GuildMembership()}),
  ],
);

/// The join and join-gate routes, in memory.
final class _GatePlane
    implements GuildManagementRepository, GuildJoinGateRepository {
  _GatePlane({this.onboarding});

  final GuildOnboarding? onboarding;
  final List<String> acceptedIn = [];
  final List<Set<String>> answers = [];

  @override
  Future<InvitePreview> previewInvite(String code) async =>
      const InvitePreview(code: 'garden', name: 'Garden', guildId: _garden);

  @override
  Future<JoinedGuild> joinGuild(String code) async => _gardenGuild();

  @override
  Future<RulesScreening?> loadRulesScreening(String guildId) async => _rules;

  @override
  Future<Member?> acceptRules({
    required String guildId,
    required RulesScreening screening,
  }) async {
    acceptedIn.add(guildId);
    return _account({guildId: const GuildMembership()});
  }

  @override
  Future<GuildOnboarding?> loadOnboarding(String guildId) async => onboarding;

  @override
  Future<Member?> answerOnboarding({
    required String guildId,
    required GuildOnboarding onboarding,
    required Set<String> chosenOptionIds,
    required DateTime seenAt,
  }) async {
    answers.add(chosenOptionIds);
    return _account({
      guildId: GuildMembership(
        roleIds: [
          for (final prompt in onboarding.prompts)
            for (final option in prompt.options)
              if (chosenOptionIds.contains(option.id)) ...option.roleIds,
        ],
      ),
    });
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// A transport that serves one fixed workspace and the gate plane.
final class _GateRepository implements ChatRepository {
  _GateRepository(this._plane, this._workspace);

  final _GatePlane _plane;
  final ChatWorkspace _workspace;
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();

  @override
  Stream<ChatRepositoryEvent> get events => _events.stream;

  @override
  GuildManagementRepository? get guildManagement => _plane;

  @override
  VoiceSignalingService? get voiceSignaling => null;

  @override
  UserProfileRepository? get userProfile => null;

  @override
  ThreadMembershipRepository? get threadMembership => null;

  @override
  StageRepository? get stages => null;

  @override
  SoundboardRepository? get soundboard => null;

  @override
  GifRepository? get gifs => null;

  @override
  ApplicationCommandRepository? get applicationCommands => null;

  @override
  MessageComponentRepository? get messageComponents => null;

  @override
  GoLiveRepository? get goLive => null;

  @override
  ConversationSummaryRepository? get conversationSummaries => null;

  @override
  UserSettingsRepository? get userSettings => null;

  @override
  ReadStateRepository? get readState => null;

  @override
  DirectCallService? get directCalls => null;

  @override
  GuildExpressionRepository? get expressions => null;

  @override
  ModerationRepository? get moderation => null;

  @override
  MessageSearchRepository? get messageSearch => null;

  @override
  PresenceService? get presence => null;

  @override
  DetectableGameRepository? get detectableGames => null;

  @override
  AccountEntitlementsRepository? get accountEntitlements => null;

  @override
  DesktopRelationshipRepository? get relationships => null;

  @override
  Future<ChatWorkspace> loadWorkspace() async => _workspace;

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
    String? aroundMessageId,
  }) async => ChannelHistoryPage(
    history: ChannelHistory(
      channelId: channelId,
      messages: const [],
      members: const [],
    ),
    hasMore: false,
  );

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) async =>
      ChannelHistory(
        channelId: channelId,
        messages: const [],
        members: const [],
      );

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) async {}

  @override
  Future<void> startTyping(String channelId) async {}

  @override
  Future<void> close() async => _events.close();

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
