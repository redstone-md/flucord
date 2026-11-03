import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/workspace_activity.dart';
import 'package:flucord/src/domain/read_state.dart';
import 'package:flucord/src/presentation/widgets/server_rail.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('renders Discord rail activity for DMs and guilds', (
    tester,
  ) async {
    String? selectedSpace;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ServerRail(
            spaces: _workspace.spaces,
            activity: _workspace.activityBySpace(),
            selectedSpaceId: CommunitySpace.directMessagesId,
            onSelectSpace: (value) => selectedSpace = value,
            onToggleTheme: () {},
            onOpenConnections: () {},
            sessionMode: SessionMode.discord,
            isDark: true,
          ),
        ),
      ),
    );

    expect(_badgeText(tester, CommunitySpace.directMessagesId), '99+');
    expect(_badgeText(tester, 'guild-1'), '3');
    expect(find.byKey(const ValueKey('space-mention-guild-2')), findsNothing);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey(
                'space-indicator-${CommunitySpace.directMessagesId}',
              ),
            ),
          )
          .height,
      20,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('space-indicator-guild-1')))
          .height,
      8,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('space-indicator-guild-2')))
          .height,
      8,
    );

    final dmSemantics = tester.getSemantics(
      find.byKey(
        const ValueKey('space-semantics-${CommunitySpace.directMessagesId}'),
      ),
    );
    final guildSemantics = tester.getSemantics(
      find.byKey(const ValueKey('space-semantics-guild-1')),
    );
    expect(dmSemantics.label, 'Direct Messages, 120 mentions');
    expect(guildSemantics.label, 'Forge, 3 mentions');

    await tester.tap(find.byKey(const ValueKey('space-guild-1')));
    expect(selectedSpace, 'guild-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rail is one even column of 40 px tiles', (tester) async {
    await _pumpRail(tester, onAddServer: () {});

    expect(tester.getSize(find.byKey(const ValueKey('server-rail'))).width, 64);
    for (final key in [
      'space-direct-messages',
      'space-guild-1',
      'space-guild-2',
      'add-server',
    ]) {
      expect(
        tester.getSize(find.byKey(ValueKey(key))),
        const Size(40, 40),
        reason: key,
      );
    }
  });

  testWidgets('the pill sits on the rail edge, centred on its tile', (
    tester,
  ) async {
    await _pumpRail(tester);

    final rail = tester.getRect(find.byKey(const ValueKey('server-rail')));
    for (final id in [CommunitySpace.directMessagesId, 'guild-1']) {
      final pill = tester.getRect(find.byKey(ValueKey('space-indicator-$id')));
      final tile = tester.getRect(_tile(id));
      expect(pill.left, rail.left, reason: id);
      expect(pill.center.dy, tile.center.dy, reason: id);
    }
  });

  testWidgets('the badge overlaps the same corner of every tile', (
    tester,
  ) async {
    await _pumpRail(tester);

    Offset badgeOffset(String id) {
      final tile = tester.getRect(_tile(id));
      final badge = tester.getRect(find.byKey(ValueKey('space-mention-$id')));
      // The badge covers the tile's bottom right corner.
      expect(badge.contains(tile.bottomRight - const Offset(1, 1)), isTrue);
      return badge.bottomRight - tile.bottomRight;
    }

    expect(
      badgeOffset(CommunitySpace.directMessagesId),
      badgeOffset('guild-1'),
    );
  });

  testWidgets('the badge is ringed in the rail colour', (tester) async {
    await _pumpRail(tester);

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byKey(const ValueKey('space-mention-guild-1')),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(
      (decoration.border! as Border).top.color,
      FlucordTheme.dark.extension<FlucordSurfaceTheme>()!.rail,
    );
  });

  testWidgets('a muted space loses its pip but keeps its mentions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ServerRail(
            spaces: _workspace.spaces,
            activity: _workspace.activityBySpace(
              readState: ReadStateSnapshot(
                settings: {
                  'guild-2': GuildNotificationSettings(
                    spaceId: 'guild-2',
                    muted: true,
                  ),
                  'guild-1': GuildNotificationSettings(
                    spaceId: 'guild-1',
                    muted: true,
                  ),
                },
              ),
            ),
            selectedSpaceId: CommunitySpace.directMessagesId,
            onSelectSpace: (_) {},
            onToggleTheme: () {},
            onOpenConnections: () {},
            sessionMode: SessionMode.discord,
            isDark: true,
          ),
        ),
      ),
    );

    // guild-2 is unread only, so muting removes its indicator entirely.
    expect(find.byKey(const ValueKey('space-indicator-guild-2')), findsNothing);
    // guild-1 is muted too, but a mention outranks a mute.
    expect(_badgeText(tester, 'guild-1'), '3');
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('space-semantics-guild-2')))
          .label,
      'Archive, muted',
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpRail(WidgetTester tester, {VoidCallback? onAddServer}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ServerRail(
            spaces: _workspace.spaces,
            activity: _workspace.activityBySpace(),
            selectedSpaceId: CommunitySpace.directMessagesId,
            onSelectSpace: (_) {},
            onToggleTheme: () {},
            onOpenConnections: () {},
            onAddServer: onAddServer,
            sessionMode: SessionMode.discord,
            isDark: true,
          ),
        ),
      ),
    );

/// The tap target of a space's tile. The DM tile has a key of its own.
Finder _tile(String spaceId) => find.byKey(
  ValueKey(
    spaceId == CommunitySpace.directMessagesId
        ? 'space-direct-messages'
        : 'space-$spaceId',
  ),
);

String _badgeText(WidgetTester tester, String spaceId) {
  final badge = find.byKey(ValueKey('space-mention-$spaceId'));
  return tester
      .widget<Text>(find.descendant(of: badge, matching: find.byType(Text)))
      .data!;
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace.directMessages(),
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
    CommunitySpace(
      id: 'guild-2',
      name: 'Archive',
      monogram: 'AR',
      colorValue: 0xff59636a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'dm-1',
      spaceId: CommunitySpace.directMessagesId,
      name: 'Jack',
      topic: '',
      kind: ChannelKind.text,
      recipientId: 'user-1',
      unread: true,
      mentionCount: 120,
    ),
    ConversationChannel(
      id: 'guild-general',
      spaceId: 'guild-1',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
      mentionCount: 2,
    ),
    ConversationChannel(
      id: 'guild-alerts',
      spaceId: 'guild-1',
      name: 'alerts',
      topic: '',
      kind: ChannelKind.text,
      mentionCount: 1,
    ),
    ConversationChannel(
      id: 'archive-general',
      spaceId: 'guild-2',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
      unread: true,
    ),
  ],
  members: const [],
  messages: const [],
  currentMemberId: 'bot-1',
);
