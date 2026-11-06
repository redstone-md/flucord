import 'package:flucord/src/application/server_profile_controller.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/presentation/profile_image_picker.dart';
import 'package:flucord/src/presentation/widgets/server_profile_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/guild_settings_fixtures.dart';

final _nickname = find.byKey(const ValueKey('server-profile-nickname'));
final _bio = find.byKey(const ValueKey('server-profile-bio'));
final _pickAvatar = find.byKey(const ValueKey('profile-pick-avatar'));
final _pickBanner = find.byKey(const ValueKey('profile-pick-banner'));
final _removeBanner = find.byKey(const ValueKey('profile-remove-banner'));
final _save = find.byKey(const ValueKey('server-profile-save'));
final _dialog = find.byKey(const ValueKey('server-profile-dialog'));

final class _StubPicker implements ProfileImagePicker {
  const _StubPicker();

  @override
  Future<ProfileImageSelection?> pick() async => const ProfileImageSelection(
    name: 'avatar.png',
    dataUri: 'data:image/png;base64,AAAA',
    byteCount: 3,
  );
}

Future<void> _open(
  WidgetTester tester,
  FakeGuildManagementRepository repository, {
  bool canChangeNickname = true,
  bool hasServerProfiles = true,
}) async {
  final workspace = guildWorkspace();
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showServerProfileDialog(
              context,
              space: workspace.spaces.single,
              self: workspace.memberById(moderatorId),
              controller: ServerProfileController(repository, guildId: guildId),
              canChangeNickname: canChangeNickname,
              hasServerProfiles: hasServerProfiles,
              imagePicker: const _StubPicker(),
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

void main() {
  testWidgets('a new nickname is the only field sent', (tester) async {
    final repository = FakeGuildManagementRepository()
      ..ownServerProfile = const OwnServerProfile(
        guildId: guildId,
        userId: moderatorId,
        nickname: 'Forge Mira',
        avatarHash: 'a1b2',
        bannerHash: 'c3d4',
        bio: 'Smith by trade.',
      );
    await _open(tester, repository);

    expect(find.text('Forge Mira'), findsOneWidget);
    expect(find.text('Smith by trade.'), findsOneWidget);

    await tester.enterText(_nickname, 'Smith');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();

    // The avatar, banner and bio were left alone, so none of them is sent.
    expect(repository.savedServerProfiles.single.toJson(), {'nick': 'Smith'});
    expect(_dialog, findsNothing);
  });

  testWidgets('an emptied nickname goes back to your own name', (tester) async {
    final repository = FakeGuildManagementRepository()
      ..ownServerProfile = const OwnServerProfile(
        guildId: guildId,
        userId: moderatorId,
        nickname: 'Forge Mira',
      );
    await _open(tester, repository);

    await tester.enterText(_nickname, '');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(repository.savedServerProfiles.single.toJson(), {'nick': null});
  });

  testWidgets('with Nitro, the avatar, banner and bio are sent as changed', (
    tester,
  ) async {
    final repository = FakeGuildManagementRepository()
      ..ownServerProfile = const OwnServerProfile(
        guildId: guildId,
        userId: moderatorId,
        bannerHash: 'c3d4',
      );
    await _open(tester, repository);

    await tester.tap(_pickAvatar);
    await tester.pumpAndSettle();
    await tester.tap(_removeBanner);
    await tester.pump();
    await tester.enterText(_bio, 'Hello');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(repository.savedServerProfiles.single.toJson(), {
      'avatar': 'data:image/png;base64,AAAA',
      'banner': null,
      'bio': 'Hello',
    });
  });

  testWidgets('without Nitro only the nickname shows', (tester) async {
    await _open(
      tester,
      FakeGuildManagementRepository(),
      hasServerProfiles: false,
    );

    expect(_nickname, findsOneWidget);
    expect(_pickAvatar, findsNothing);
    expect(_pickBanner, findsNothing);
    expect(_bio, findsNothing);
  });

  testWidgets('without CHANGE_NICKNAME there is no nickname field', (
    tester,
  ) async {
    await _open(
      tester,
      FakeGuildManagementRepository(),
      canChangeNickname: false,
    );

    expect(_nickname, findsNothing);
    expect(_pickAvatar, findsOneWidget);
  });

  testWidgets('a refusal is said plainly and the dialog stays open', (
    tester,
  ) async {
    final repository = FakeGuildManagementRepository()
      ..nextServerProfileRefusal = const ServerProfileRefusal(
        'This server does not let you change that.',
      );
    await _open(tester, repository);

    await tester.enterText(_nickname, 'Smith');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(
      find.text('This server does not let you change that.'),
      findsOneWidget,
    );
    expect(_dialog, findsOneWidget);
  });

  testWidgets('Save waits for a change', (tester) async {
    await _open(tester, FakeGuildManagementRepository());

    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(_dialog, findsOneWidget);
  });
}
