import 'package:flucord/src/app.dart';
import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _conversationLink = 'https://discord.com/channels/forge/forge-design/m5';
const _foreignLink = 'https://discord.com/channels/ghost/ghost-hall/m99';

void main() {
  testWidgets('a message link in a sent message navigates inside the app', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final launcher = _RecordingLauncher();

    await tester.pumpWidget(
      FlucordApp(
        bootstrap: AppBootstrap(
          initialRepository: MockChatRepository(latency: Duration.zero),
          initialSessionMode: SessionMode.demo,
          externalLinkLauncher: launcher,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // The timeline starts on forge-general, a different channel than the
    // link names, so a successful navigation has somewhere to move to.
    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      _conversationLink,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // The link span is a gesture inside a paragraph-wide RichText, so the
    // tap aims at the glyphs rather than the widget's centre.
    final linkTopLeft = tester.getTopLeft(
      find.text(_conversationLink, findRichText: true),
    );
    await tester.tapAt(linkTopLeft + const Offset(20, 8));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // The header names the linked channel and the timeline shows the message
    // the link lands on, neither of which the starting view offered.
    expect(find.text('design'), findsWidgets);
    expect(find.byKey(const ValueKey('message-m5')), findsOneWidget);
    expect(
      launcher.opened,
      isEmpty,
      reason: 'a reachable link must not open a browser',
    );
  });

  testWidgets('a link to an unjoined server stays with the launcher', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final launcher = _RecordingLauncher();

    await tester.pumpWidget(
      FlucordApp(
        bootstrap: AppBootstrap(
          initialRepository: MockChatRepository(latency: Duration.zero),
          initialSessionMode: SessionMode.demo,
          externalLinkLauncher: launcher,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      _foreignLink,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final foreignTopLeft = tester.getTopLeft(
      find.text(_foreignLink, findRichText: true),
    );
    await tester.tapAt(foreignTopLeft + const Offset(20, 8));
    await tester.pumpAndSettle();

    // Nothing moved and the browser was asked to show the page.
    expect(find.byKey(const ValueKey('message-m5')), findsNothing);
    expect(launcher.opened.single.toString(), _foreignLink);
  });
}

final class _RecordingLauncher implements ExternalLinkLauncher {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}
