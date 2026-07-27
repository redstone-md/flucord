part of 'guild_settings_controller_test.dart';

void _structureCases() {
  group('roles', () {
    test('creates, edits and deletes, keeping the list ordered', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.roles);
      expect(controller.roles.map((role) => role.id), [
        'moderator',
        'member',
        guildId,
      ]);

      expect(
        await controller.createRole(const GuildRoleDraft(name: 'new role')),
        isTrue,
      );
      expect(controller.roles.map((role) => role.name), contains('new role'));

      final member = controller.roles.firstWhere((role) => role.id == 'member');
      final edit = GuildRoleEdit()..name = 'members';
      expect(await controller.saveRole(member, edit), isTrue);
      expect(
        controller.roles.firstWhere((role) => role.id == 'member').name,
        'members',
      );

      expect(await controller.deleteRole(member), isTrue);
      expect(
        controller.roles.map((role) => role.id),
        isNot(contains('member')),
      );
    });

    test('an empty role edit is never sent', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.roles);
      repository.calls.clear();
      final member = controller.roles.firstWhere((role) => role.id == 'member');
      expect(await controller.saveRole(member, GuildRoleEdit()), isFalse);
      expect(repository.calls, isEmpty);
    });

    test('a role at or above the actor cannot be edited or deleted', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.roles);
      final own = controller.roles.firstWhere((role) => role.id == 'moderator');
      expect(controller.canEditRole(own), isFalse);
      expect(controller.canDeleteRole(own), isFalse);
      expect(
        await controller.saveRole(own, GuildRoleEdit()..hoist = true),
        isFalse,
      );
      expect(await controller.deleteRole(own), isFalse);
    });

    test('an integration-managed role is never editable', () async {
      final repository = FakeGuildManagementRepository()..includeManaged = true;
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.roles);
      final bot = controller.roles.firstWhere((role) => role.id == 'bot');
      expect(controller.canEditRole(bot), isFalse);
      expect(controller.canDeleteRole(bot), isFalse);
    });

    test('@everyone cannot be deleted even by a permitted moderator', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.roles);
      final everyone = controller.roles.firstWhere(
        (role) => role.id == guildId,
      );
      expect(controller.canDeleteRole(everyone), isFalse);
    });

    test('moving a role sends the whole reorder', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.roles);
      // `member` is below the actor's own role, and the row above it is the
      // actor's role, which they may not displace.
      final member = controller.roles.firstWhere((role) => role.id == 'member');
      expect(await controller.moveRole(member, offset: -1), isFalse);
      expect(await controller.moveRole(member, offset: 0), isFalse);
      // Moving down would swap with @everyone, which is pinned.
      expect(await controller.moveRole(member, offset: 1), isFalse);
      expect(repository.reorderedDeltas, isNull);
    });

    test('a reorder between two editable roles goes through', () async {
      final repository = FakeGuildManagementRepository()
        ..includeLowRoles = true;
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.roles);
      final member = controller.roles.firstWhere((role) => role.id == 'member');
      expect(controller.roles.map((role) => role.id).toList(), [
        'moderator',
        'helper',
        'member',
        guildId,
      ]);
      expect(await controller.moveRole(member, offset: -1), isTrue);
      expect(repository.reorderedDeltas, isNotNull);
      expect(controller.roles.map((role) => role.id).toList(), [
        'moderator',
        'member',
        'helper',
        guildId,
      ]);
    });

    test('a move off the end of the list does nothing', () async {
      final repository = FakeGuildManagementRepository()
        ..includeLowRoles = true;
      final controller = _controller(repository: repository);
      await controller.openSection(GuildSettingsSection.roles);
      final lowest = controller.roles.firstWhere((role) => role.id == 'helper');
      expect(await controller.moveRole(lowest, offset: 5), isFalse);
    });
  });

  group('channels', () {
    test(
      'create, edit, delete and reorder are gated on MANAGE_CHANNELS',
      () async {
        final repository = FakeGuildManagementRepository();
        final controller = _controller(
          repository: repository,
          permissions: DiscordPermissions.manageGuild,
        );
        expect(
          await controller.createChannel(
            const GuildChannelDraft(type: GuildChannelType.text, name: 'x'),
          ),
          isFalse,
        );
        expect(
          await controller.saveChannel(
            channelId: 'c',
            edit: GuildChannelEdit()..name = 'x',
          ),
          isFalse,
        );
        expect(await controller.deleteChannel('c'), isFalse);
        expect(
          await controller.reorderChannels(before: const [], after: const []),
          isFalse,
        );
        expect(repository.calls, isEmpty);
      },
    );

    test('an empty channel edit is never sent', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      expect(
        await controller.saveChannel(channelId: 'c', edit: GuildChannelEdit()),
        isFalse,
      );
      expect(repository.calls, isEmpty);
    });

    test('a reorder that changes nothing is never sent', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      const entries = [
        ChannelOrderEntry(
          id: '222222222222222222',
          position: 0,
          type: GuildChannelType.text,
        ),
      ];
      expect(
        await controller.reorderChannels(before: entries, after: entries),
        isFalse,
      );
      expect(repository.calls, isEmpty);
    });

    test('a real reorder reaches the repository', () async {
      final repository = FakeGuildManagementRepository();
      final controller = _controller(repository: repository);
      const before = [
        ChannelOrderEntry(
          id: '222222222222222222',
          position: 0,
          type: GuildChannelType.text,
        ),
        ChannelOrderEntry(
          id: '333333333333333333',
          position: 1,
          type: GuildChannelType.text,
        ),
      ];
      expect(
        await controller.reorderChannels(
          before: before,
          after: [before[1], before[0]],
        ),
        isTrue,
      );
      expect(repository.calls, contains('reorderGuildChannels'));
      expect(
        await controller.createChannel(
          const GuildChannelDraft(type: GuildChannelType.text, name: 'x'),
        ),
        isTrue,
      );
      expect(
        await controller.saveChannel(
          channelId: 'c',
          edit: GuildChannelEdit()..name = 'x',
        ),
        isTrue,
      );
      expect(await controller.deleteChannel('c'), isTrue);
    });
  });
}
