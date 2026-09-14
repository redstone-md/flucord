import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';

void main() {
  testWidgets('navigates, searches, and sends a message', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('The Forge'), findsOneWidget);
    expect(
      find.textContaining('Ship the vertical slice first'),
      findsOneWidget,
    );
    expect(find.text('transport-boundary.md'), findsOneWidget);
    expect(find.text('release-checklist'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toggle-pins')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pinned-messages-panel')), findsOneWidget);
    expect(find.byTooltip('Unpin message'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-pins-panel')));
    await tester.pump();
    expect(find.byKey(const ValueKey('pinned-messages-panel')), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('message-m4'))),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Reply'));
    await tester.pump();
    expect(find.text('Replying to Jack'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel reply'));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('open-connections')));
    await tester.pumpAndSettle();
    expect(find.text('Connections'), findsOneWidget);
    expect(find.text('Sign in with QR code'), findsOneWidget);
    expect(find.text('Connect Discord'), findsNothing);
    expect(find.byKey(const ValueKey('discord-bot-token')), findsNothing);
    expect(find.byKey(const ValueKey('developer-bot-transport')), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('channel-forge-design')));
    await tester.pumpAndSettle();
    expect(find.textContaining('continuous signal'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('message-search')),
      'copper',
    );
    await tester.pump();
    expect(find.textContaining('copper only for warnings'), findsOneWidget);
    expect(find.textContaining('continuous signal'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('message-search')), '');
    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'Native message path confirmed.',
    );
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Native message path confirmed.'), findsOneWidget);
  });

  testWidgets('opens pinned messages without compact layout overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-pins')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pinned-messages-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('browses active and archived threads from the header', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('channel-forge-native')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-threads')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('thread-browser-panel')), findsOneWidget);
    expect(find.text('ACTIVE THREADS'), findsOneWidget);
    expect(find.text('ARCHIVED THREADS'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('thread-row-forge-thread-release')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('thread-row-archived-forge-native-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('channel-archived-forge-native-1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('load-more-archived-threads')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('thread-row-archived-forge-native-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('load-more-archived-threads')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('thread-row-archived-forge-native-2')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('transport-notes'), findsWidgets);
    expect(find.byKey(const ValueKey('locked-thread-notice')), findsOneWidget);
    expect(find.byKey(const ValueKey('message-composer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens threads without compact layout overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-threads')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('thread-browser-panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('thread-row-archived-forge-general-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters, pages, and creates a native forum post', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('channel-forge-forum-bootstrap')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('channel-forge-forum')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('forum-post-feed')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('forum-post-forge-forum-bootstrap')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('forum-post-archived-forge-forum-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('forum-filter-tag-client')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('forum-post-forge-forum-bootstrap')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('forum-post-archived-forge-forum-1')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('forum-filter-tag-client')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('load-more-forum-posts')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('forum-post-archived-forge-forum-2')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('create-forum-post')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('forum-post-name')),
      'SQLite v13 report',
    );
    await tester.enterText(
      find.byKey(const ValueKey('forum-post-content')),
      'Forum metadata survives a native restart.',
    );
    await tester.tap(find.byKey(const ValueKey('forum-post-tag-tag-client')));
    await tester.tap(find.byKey(const ValueKey('create-forum-post-confirm')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('SQLite v13 report'), findsWidgets);
    expect(
      find.text('Forum metadata survives a native restart.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the forum feed without compact layout overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Choose channel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forum: field-reports'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('forum-post-feed')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens a direct message from the native member profile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('member-row-mira')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('member-profile-popover')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('message-member')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Direct Messages'), findsOneWidget);
    expect(find.text('User mira'), findsWidgets);
    expect(find.byKey(const ValueKey('member-profile-popover')), findsNothing);
  });

  testWidgets('opens native voice controls without media plugins', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('channel-forge-voice')));
    await tester.pumpAndSettle();

    // Opening the channel shows the room rather than walking into it: the
    // microphone stays shut and nobody is announced until the button.
    expect(find.byKey(const ValueKey('voice-channel-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-connection-bar')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('voice-channel-join')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // Twice over: the room says it, and so does the strip that keeps the
    // connection reachable after navigating away from the room.
    expect(find.byKey(const ValueKey('voice-channel-preview')), findsNothing);
    expect(find.text('Local media ready'), findsWidgets);
    expect(find.byKey(const ValueKey('voice-connection-bar')), findsOneWidget);
    // Not in the room: which microphone to use belongs to the machine, and
    // lives in settings under Voice & Video.
    expect(find.text('Input device'), findsNothing);
    expect(find.byKey(const ValueKey('voice-mute')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-mute')));
    await tester.pumpAndSettle();
    // Both places agree: the room and the strip that stays reachable after
    // navigating away. The strip used not to redraw, so it kept saying Mute
    // while the room said Unmute.
    expect(find.byTooltip('Unmute'), findsNWidgets(2));

    // One share control, in the toolbar: the room used to carry a local
    // capture button and a Go Live button, which looked like a choice and was
    // not one — only Go Live puts a picture in the channel.
    expect(find.byKey(const ValueKey('voice-share-screen')), findsNothing);
    // Present but refused: this transport has no stream plane, and a control
    // that disappeared would leave somebody hunting for a button.
    final share = tester.widget<IconButton>(
      find.byKey(const ValueKey('go-live-toggle')),
    );
    expect(share.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('voice-disconnect')));
    await tester.pumpAndSettle();
    // Leaving puts the channel back to what it looks like before joining:
    // the room with a button, not a room saying it is disconnected.
    expect(find.byKey(const ValueKey('voice-channel-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-connection-bar')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
