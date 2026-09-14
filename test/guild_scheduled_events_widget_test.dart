import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/guild_scheduled_events_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('renders responsive event states and returns a voice channel', (
    tester,
  ) async {
    String? selectedChannelId;
    await tester.binding.setSurfaceSize(const Size(560, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selectedChannelId = await showDialog<String>(
                context: context,
                builder: (_) => GuildScheduledEventsDialog(
                  space: _workspace.spaces.single,
                  workspace: _workspace,
                  events: _events,
                  isLoading: false,
                  error: null,
                  onRefresh: () {},
                ),
              );
            },
            child: const Text('Open events'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open events'));
    await tester.pumpAndSettle();
    expect(find.text('HAPPENING NOW'), findsOneWidget);
    expect(find.text('LIVE NOW'), findsOneWidget);
    expect(find.text('UPCOMING'), findsOneWidget);
    expect(find.text('18 interested'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guild-event-active')));
    await tester.pumpAndSettle();
    expect(selectedChannelId, 'voice-1');
    expect(find.byKey(const ValueKey('guild-events-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps event failure retry in place', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: GuildScheduledEventsDialog(
          space: _workspace.spaces.single,
          workspace: _workspace,
          events: const [],
          isLoading: false,
          error: StateError('offline'),
          onRefresh: () => retries++,
        ),
      ),
    );
    expect(find.text('Events unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'voice-1',
      spaceId: 'guild-1',
      name: 'workbench',
      topic: '',
      kind: ChannelKind.voice,
    ),
  ],
  members: const [],
  messages: const [],
  currentMemberId: 'bot-1',
);

final _events = [
  GuildScheduledEvent(
    id: 'active',
    spaceId: 'guild-1',
    channelId: 'voice-1',
    name: 'Native client review',
    scheduledStartTime: DateTime.now(),
    entityType: GuildScheduledEventEntityType.voice,
    status: GuildScheduledEventStatus.active,
    interestedCount: 18,
  ),
  GuildScheduledEvent(
    id: 'upcoming',
    spaceId: 'guild-1',
    name: 'Release checkpoint',
    location: 'Build room',
    scheduledStartTime: DateTime.now().add(const Duration(days: 1)),
    entityType: GuildScheduledEventEntityType.external,
    status: GuildScheduledEventStatus.scheduled,
    interestedCount: 9,
  ),
];
