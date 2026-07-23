import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/thread_browser_panel.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('shows the initial archived thread loading state', (
    tester,
  ) async {
    await _pumpPanel(tester, isLoading: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No threads yet'), findsNothing);
  });

  testWidgets('shows the archived thread error and retry state', (
    tester,
  ) async {
    var retries = 0;
    await _pumpPanel(
      tester,
      error: StateError('offline'),
      onRefresh: () => retries++,
    );

    expect(find.text('Threads unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('shows the empty thread state', (tester) async {
    await _pumpPanel(tester);

    expect(find.text('No threads yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  bool isLoading = false,
  Object? error,
  VoidCallback? onRefresh,
}) => tester.pumpWidget(
  MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Align(
        alignment: Alignment.centerRight,
        child: ThreadBrowserPanel(
          parentChannel: _parent,
          activeThreads: const [],
          archivedThreads: const [],
          isLoading: isLoading,
          error: error,
          canLoadMore: false,
          onClose: () {},
          onRefresh: onRefresh ?? () {},
          onLoadMore: () {},
          onSelectThread: (_) {},
        ),
      ),
    ),
  ),
);

const _parent = ConversationChannel(
  id: 'channel-1',
  spaceId: 'guild-1',
  name: 'native-client',
  topic: '',
  kind: ChannelKind.text,
);
