import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/presentation/widgets/invite_people_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _space = CommunitySpace(
  id: '111111111111111111',
  name: 'The Forge',
  monogram: 'TF',
  colorValue: 0xff456b5a,
);

const _channel = ConversationChannel(
  id: '222222222222222222',
  spaceId: '111111111111111111',
  name: 'general',
  topic: '',
  kind: ChannelKind.text,
);

/// Answers each ask with a new code, and keeps the options it was asked with.
final class _Invites {
  final List<InviteOptions> asked = [];
  Object? failure;

  Future<GuildInvite> create(InviteOptions options) async {
    asked.add(options);
    if (failure case final error?) throw error;
    return GuildInvite(
      code: 'code${asked.length}',
      maxAgeSeconds: options.maxAgeSeconds,
      maxUses: options.maxUses,
    );
  }
}

Future<void> _open(WidgetTester tester, _Invites invites) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showInvitePeopleDialog(
              context,
              space: _space,
              channel: _channel,
              createInvite: invites.create,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String field, String label) async {
  await tester.tap(find.byKey(ValueKey(field)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens with a ready link that copies', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    final invites = _Invites();
    await _open(tester, invites);

    expect(find.text('Invite friends to The Forge'), findsOneWidget);
    // Discord's own dialog starts at seven days and no limit on uses.
    expect(invites.asked.single.maxAgeSeconds, 604800);
    expect(invites.asked.single.maxUses, 0);
    expect(find.text('https://discord.gg/code1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('invite-people-copy')));
    await tester.pumpAndSettle();
    expect(copied, ['https://discord.gg/code1']);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('changing expiry or uses makes a link with those limits', (
    tester,
  ) async {
    final invites = _Invites();
    await _open(tester, invites);

    await _choose(tester, 'invite-people-expiry', 'Never');
    expect(invites.asked.last.maxAgeSeconds, 0);
    expect(find.text('https://discord.gg/code2'), findsOneWidget);

    await _choose(tester, 'invite-people-uses', '5 uses');
    expect(invites.asked.last.maxAgeSeconds, 0);
    expect(invites.asked.last.maxUses, 5);
    expect(find.text('https://discord.gg/code3'), findsOneWidget);
  });

  testWidgets('a refused invite says so and can be asked again', (
    tester,
  ) async {
    final invites = _Invites()..failure = StateError('refused');
    await _open(tester, invites);

    expect(find.text('Discord did not make an invite link.'), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-people-copy')), findsNothing);

    invites.failure = null;
    await tester.tap(find.byKey(const ValueKey('invite-people-retry')));
    await tester.pumpAndSettle();
    expect(find.text('https://discord.gg/code2'), findsOneWidget);
  });
}
