import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/member_avatar.dart';
import 'package:flucord/src/presentation/widgets/server_rail.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('selects guild avatar and keeps initials fallback', (
    tester,
  ) async {
    const member = Member(
      id: 'user-1',
      displayName: 'Jack',
      initials: 'JK',
      role: 'Operator',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      avatarUrl: 'https://cdn.example/global.webp',
      avatarUrlsBySpace: {'guild-1': 'https://cdn.example/guild.webp'},
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MemberAvatar(member: member, spaceId: 'guild-1'),
        ),
      ),
    );

    expect(find.text('JK'), findsOneWidget);
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('member-avatar-image-user-1')),
    );
    expect((image.image as NetworkImage).url, endsWith('/guild.webp'));
  });

  testWidgets('renders initials without a remote identity', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MemberAvatar(
            member: Member(
              id: 'local',
              displayName: 'Local',
              initials: 'LO',
              role: 'Member',
              presence: Presence.offline,
              colorValue: 0xff456b5a,
            ),
          ),
        ),
      ),
    );

    expect(find.text('LO'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server rail renders guild and current member identity', (
    tester,
  ) async {
    final workspace = ChatWorkspace(
      spaces: const [
        CommunitySpace(
          id: 'guild-1',
          name: 'The Forge',
          monogram: 'TF',
          colorValue: 0xff456b5a,
          iconUrl: 'https://cdn.example/guild-icon.webp',
        ),
      ],
      channels: const [],
      members: const [
        Member(
          id: 'user-1',
          displayName: 'Jack',
          initials: 'JK',
          role: 'Operator',
          presence: Presence.online,
          colorValue: 0xff456b5a,
          avatarUrl: 'https://cdn.example/avatar.webp',
        ),
      ],
      messages: const [],
      currentMemberId: 'user-1',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ServerRail(
            workspace: workspace,
            selectedSpaceId: 'guild-1',
            onSelectSpace: (_) {},
            onToggleTheme: () {},
            onOpenConnections: () {},
            sessionMode: SessionMode.discordBot,
            isDark: true,
          ),
        ),
      ),
    );

    final guildIcon = tester.widget<Image>(
      find.byKey(const ValueKey('space-icon-guild-1')),
    );
    expect((guildIcon.image as NetworkImage).url, endsWith('guild-icon.webp'));
    expect(
      find.byKey(const ValueKey('member-avatar-image-user-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
