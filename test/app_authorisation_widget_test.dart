import 'package:flucord/src/application/app_authorisation_controller.dart';
import 'package:flucord/src/domain/app_authorisation.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/presentation/widgets/user_settings_apps_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _inviteUrl =
    'https://discord.com/oauth2/authorize?client_id=978270835341422'
    '&scope=bot+applications.commands&permissions=8';

const _guild = 'guild-1';
const _me = 'member-1';

Future<AppAuthorisationController> _pump(
  WidgetTester tester, {
  AppAuthorisationRepository? repository,
  ChatWorkspace? workspace,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = AppAuthorisationController(
    () => repository,
    () => workspace,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AppAuthorisationSection(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _readInvite(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('app-invite-link')),
    _inviteUrl,
  );
  await tester.tap(find.byKey(const ValueKey('app-invite-read')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('states what an invite asks before consent', (tester) async {
    await _pump(
      tester,
      repository: _FakeAuthorisation(),
      workspace: _workspace,
    );
    await _readInvite(tester);

    expect(find.text('Helper Bot'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-invite-scopes')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-invite-scope-bot')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('app-invite-scope-applications.commands')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('app-invite-permission-Administrator')),
      findsOneWidget,
    );
  });

  testWidgets('a link that is not an app invite leaves the page empty', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeAuthorisation(),
      workspace: _workspace,
    );

    await tester.enterText(
      find.byKey(const ValueKey('app-invite-link')),
      'https://discord.gg/abc',
    );
    await tester.tap(find.byKey(const ValueKey('app-invite-read')));
    await tester.pumpAndSettle();

    // The answer to "what does this ask for" is "nothing": the page says
    // what an invite looks like again rather than showing a stale app.
    expect(find.byKey(const ValueKey('app-invite-idle')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-invite-application')), findsNothing);
  });

  testWidgets('a server with no managers offers no consent', (tester) async {
    final controller = await _pump(
      tester,
      repository: _FakeAuthorisation(),
      workspace: null,
    );
    await _readInvite(tester);

    expect(controller.selectedGuildId, isNull);
    expect(find.byKey(const ValueKey('app-invite-consent')), findsNothing);
    expect(find.byKey(const ValueKey('app-invite-no-guilds')), findsOneWidget);
  });

  testWidgets('consent adds the app to the picked server', (tester) async {
    final repository = _FakeAuthorisation();
    await _pump(tester, repository: repository, workspace: _workspace);
    await _readInvite(tester);

    expect(
      find.byKey(const ValueKey('app-invite-guild-$_guild')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('app-invite-consent')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-invite-added')), findsOneWidget);
    expect(repository.consentedGuild, _guild);
  });

  testWidgets('a private app says who can add it', (tester) async {
    await _pump(
      tester,
      repository: _FakeAuthorisation()..public = false,
      workspace: _workspace,
    );
    await _readInvite(tester);

    expect(find.byKey(const ValueKey('app-invite-private')), findsOneWidget);
  });

  testWidgets('an add that was refused names which refusal', (tester) async {
    await _pump(
      tester,
      repository: _FakeAuthorisation()
        ..refuseWith = AppAuthorisationFailure.refused,
      workspace: _workspace,
    );
    await _readInvite(tester);

    await tester.tap(find.byKey(const ValueKey('app-invite-consent')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-invite-refusal')), findsOneWidget);
    expect(find.textContaining('refused to add it'), findsOneWidget);
  });

  testWidgets('an idle page explains what an invite looks like', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeAuthorisation(),
      workspace: _workspace,
    );

    expect(find.byKey(const ValueKey('app-invite-idle')), findsOneWidget);
  });

  testWidgets('the grants this account made are listed with their scopes', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeAuthorisation()
        ..grants = const [
          AuthorisedApplication(
            applicationId: '978270835341422',
            name: 'Helper Bot',
            description: 'Helps with things.',
            scopes: ['bot', 'applications.commands'],
          ),
        ],
      workspace: _workspace,
    );

    expect(
      find.byKey(const ValueKey('app-grant-978270835341422')),
      findsOneWidget,
    );
    expect(find.text('Helper Bot'), findsOneWidget);
    expect(find.text('Helps with things.'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-grant-scope-bot')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('app-grant-scope-applications.commands')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('app-grant-revoke-978270835341422')),
      findsOneWidget,
    );
  });

  testWidgets('revoking a grant takes its row away', (tester) async {
    final repository = _FakeAuthorisation()
      ..grants = const [
        AuthorisedApplication(
          applicationId: '978270835341422',
          name: 'Helper Bot',
        ),
      ];
    await _pump(tester, repository: repository, workspace: _workspace);

    await tester.tap(
      find.byKey(const ValueKey('app-grant-revoke-978270835341422')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('app-grant-978270835341422')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('app-grants-none')), findsOneWidget);
    expect(repository.grants, isEmpty);
  });

  testWidgets('a revoke Discord refused is named, not read as an outage', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeAuthorisation()
        ..grants = const [
          AuthorisedApplication(
            applicationId: '978270835341422',
            name: 'Helper Bot',
          ),
        ]
        ..refuseRevoke = true,
      workspace: _workspace,
    );

    await tester.tap(
      find.byKey(const ValueKey('app-grant-revoke-978270835341422')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('app-grants-revoke-refused')),
      findsOneWidget,
    );
    expect(find.textContaining('refused to remove Helper Bot'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('app-grant-978270835341422')),
      findsOneWidget,
    );
  });

  testWidgets('a failed read shows the error and the retry works', (
    tester,
  ) async {
    final repository = _FakeAuthorisation()..failNextApplication = true;
    final controller = await _pump(
      tester,
      repository: repository,
      workspace: _workspace,
    );
    await tester.enterText(
      find.byKey(const ValueKey('app-invite-link')),
      _inviteUrl,
    );
    await tester.tap(find.byKey(const ValueKey('app-invite-read')));
    await tester.pumpAndSettle();

    // The error is the page's answer to the read, reachable whatever stage
    // the controller stopped in, and it carries its own way back.
    expect(find.byKey(const ValueKey('app-invite-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-invite-reading')), findsNothing);
    expect(find.byKey(const ValueKey('app-invite-retry')), findsOneWidget);
    expect(controller.stage, AppAuthorisationStage.readingInvite);

    repository.failNextApplication = false;
    await tester.tap(find.byKey(const ValueKey('app-invite-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-invite-error')), findsNothing);
    expect(find.text('Helper Bot'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-invite-consent')), findsOneWidget);
  });

  testWidgets('an account with no grants says so', (tester) async {
    await _pump(
      tester,
      repository: _FakeAuthorisation(),
      workspace: _workspace,
    );

    expect(find.byKey(const ValueKey('app-grants-none')), findsOneWidget);
  });
}

final ChatWorkspace _workspace = ChatWorkspace(
  spaces: [
    CommunitySpace(
      id: _guild,
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [],
  roles: [
    CommunityRole(
      id: _guild,
      spaceId: _guild,
      name: '@everyone',
      position: 0,
      permissions: DiscordPermissions.manageGuild,
    ),
  ],
  members: [
    Member(
      id: _me,
      displayName: 'Ada',
      initials: 'A',
      role: 'Member',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: const {_guild},
      membershipsBySpace: const {_guild: GuildMembership()},
    ),
  ],
  messages: const [],
  currentMemberId: _me,
);

final class _FakeAuthorisation implements AppAuthorisationRepository {
  bool public = true;
  bool failNextApplication = false;
  AppAuthorisationFailure? refuseWith;
  String? consentedGuild;

  List<AuthorisedApplication> grants = const [];
  bool refuseRevoke = false;

  @override
  Future<List<AuthorisedApplication>> loadAuthorisedApplications() async =>
      grants;

  @override
  Future<void> revokeAuthorisedApplication(
    AuthorisedApplication application,
  ) async {
    if (refuseRevoke) {
      throw const AppAuthorisationException(AppAuthorisationFailure.refused);
    }
    grants = [
      for (final other in grants)
        if (other != application) other,
    ];
  }

  @override
  AppInvite? parseInvite(Uri uri) {
    if (uri.host != 'discord.com' || uri.path != '/oauth2/authorize') {
      return null;
    }
    final clientId = uri.queryParameters['client_id'];
    final scopes = AppInvite.parseScopes(uri.queryParameters['scope']);
    if (clientId == null || scopes.isEmpty) return null;
    return AppInvite(
      applicationId: clientId,
      scopes: scopes,
      permissions: DiscordPermissions.tryParse(
        uri.queryParameters['permissions'],
      ),
    );
  }

  @override
  Future<AppInviteApplication> loadApplication(String applicationId) async {
    if (failNextApplication) {
      failNextApplication = false;
      throw StateError('application failed');
    }
    return AppInviteApplication(
      id: applicationId,
      name: 'Helper Bot',
      description: 'Helps with things.',
      isPublic: public,
    );
  }

  @override
  Future<void> consent({
    required AppInvite invite,
    required String guildId,
  }) async {
    if (refuseWith case final failure?) {
      throw AppAuthorisationException(failure);
    }
    consentedGuild = guildId;
  }
}
