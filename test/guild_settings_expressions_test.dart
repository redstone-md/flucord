import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/guild_settings_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/guild_expression_errors.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';

import 'support/fake_expression_repository.dart';
import 'support/guild_settings_fixtures.dart';

GuildSettingsController _controller(
  FakeExpressionRepository repository, {
  BigInt? permissions,
  SoundboardRepository? soundboard,
}) => GuildSettingsController(
  FakeGuildManagementRepository(),
  WorkspacePermissions(
    guildWorkspace(
      moderatorPermissions: permissions ?? allModerationPermissions,
    ),
    memberId: moderatorId,
  ).administrationOf(guildId),
  guildId: guildId,
  expressions: repository,
  soundboard: soundboard,
);

void main() {
  test(
    'the expressions section is not offered without the permission or the plane',
    () async {
      final repository = FakeExpressionRepository();
      final withoutPermission = _controller(
        repository,
        permissions: DiscordPermissions.manageGuild,
      );
      expect(
        withoutPermission.availableSections,
        isNot(contains(GuildSettingsSection.expressions)),
      );

      final withoutPlane = GuildSettingsController(
        FakeGuildManagementRepository(),
        WorkspacePermissions(
          guildWorkspace(),
          memberId: moderatorId,
        ).administrationOf(guildId),
        guildId: guildId,
      );
      expect(
        withoutPlane.availableSections,
        isNot(contains(GuildSettingsSection.expressions)),
      );
      expect(repository.calls, isEmpty);
    },
  );

  test('the page lists the three kinds from the repositories', () async {
    final repository = FakeExpressionRepository()
      ..emojiByGuild[guildId] = [
        const GuildEmoji(id: 'e1', spaceId: guildId, name: 'spark'),
      ]
      ..stickersByGuild[guildId] = [
        GuildSticker(
          item: const MessageSticker(
            id: 's1',
            name: 'seal',
            format: StickerFormat.png,
            url: 'https://cdn.discordapp.com/stickers/s1.png',
          ),
          spaceId: guildId,
          tags: const ['seal'],
          available: true,
        ),
      ]
      ..soundsByGuild[guildId] = [
        const SoundboardSound(
          id: 'so1',
          name: 'airhorn',
          guildId: guildId,
          volume: 0.5,
        ),
      ];
    final soundboard = FakeSoundboardRepository()
      ..byGuild[guildId] = [
        const SoundboardSound(
          id: 'so1',
          name: 'airhorn',
          guildId: guildId,
          volume: 0.5,
        ),
        // A default sound belongs to nobody's server and is not listed.
        const SoundboardSound(id: 'default-1', name: 'boo'),
      ];
    final controller = _controller(repository, soundboard: soundboard);

    await controller.openSection(GuildSettingsSection.expressions);

    expect(controller.emoji.single.name, 'spark');
    expect(controller.stickers.single.name, 'seal');
    expect(controller.sounds.single.name, 'airhorn');
    expect(controller.sounds.single.volume, 0.5);
    // The shared default sound is listed by the picker but not by this page:
    // it is nobody's server's to delete.
    expect(controller.sounds, hasLength(1));
  });

  test(
    'an emoji upload takes a name and the image reaches the route',
    () async {
      final repository = FakeExpressionRepository();
      final controller = _controller(repository);

      final uploaded = await controller.uploadEmoji(
        name: 'forge_spark',
        dataUri: 'data:image/png;base64,QUJD',
      );

      expect(uploaded, isTrue);
      expect(repository.uploads.single.kind, 'emoji');
      expect(repository.uploads.single.name, 'forge_spark');
      expect(repository.uploads.single.dataUri, 'data:image/png;base64,QUJD');
      expect(controller.emoji.single.messageSyntax, '<:forge_spark:emoji-0>');
    },
  );

  test(
    'a sticker upload carries the format constraints in its answer',
    () async {
      final repository = FakeExpressionRepository();
      final controller = _controller(repository);

      final uploaded = await controller.uploadSticker(
        name: 'seal_of_approval',
        description: 'A seal claps.',
        tags: 'seal',
        dataUri: 'data:image/png;base64,QUJD',
      );

      expect(uploaded, isTrue);
      expect(repository.uploads.single.kind, 'sticker');
      expect(repository.uploads.single.name, 'seal_of_approval');
      expect(controller.stickers.single.item.format, StickerFormat.png);
      expect(controller.stickers.single.description, 'A seal claps.');
    },
  );

  test('a sound upload carries the name and the volume', () async {
    final repository = FakeExpressionRepository();
    final controller = _controller(repository);

    final uploaded = await controller.uploadSound(
      name: 'airhorn',
      volume: 0.4,
      dataUri: 'data:audio/mpeg;base64,QUJD',
    );

    expect(uploaded, isTrue);
    expect(repository.uploads.single.kind, 'sound');
    expect(repository.uploads.single.name, 'airhorn');
    expect(controller.sounds.single.volume, 0.4);
  });

  test('a delete reaches the route and clears the page', () async {
    final repository = FakeExpressionRepository()
      ..emojiByGuild[guildId] = [
        const GuildEmoji(id: 'e1', spaceId: guildId, name: 'spark'),
      ];
    final controller = _controller(repository);
    await controller.openSection(GuildSettingsSection.expressions);

    final deleted = await controller.deleteEmoji(controller.emoji.single);

    expect(deleted, isTrue);
    expect(repository.deletes.single, (kind: 'emoji', id: 'e1'));
    expect(controller.emoji, isEmpty);
  });

  test('sticker and sound deletes reach their routes', () async {
    final repository = FakeExpressionRepository();
    final controller = _controller(repository);
    await controller.openSection(GuildSettingsSection.expressions);

    await controller.uploadSticker(
      name: 'seal',
      description: '',
      tags: 'seal',
      dataUri: 'data:image/png;base64,QUJD',
    );
    await controller.uploadSound(
      name: 'airhorn',
      volume: 1,
      dataUri: 'data:audio/mpeg;base64,QUJD',
    );

    expect(await controller.deleteSticker(controller.stickers.single), isTrue);
    expect(await controller.deleteSound(controller.sounds.single), isTrue);
    expect(
      repository.deletes.map((entry) => entry.kind),
      unorderedEquals(['sticker', 'sound']),
    );
    expect(controller.stickers, isEmpty);
    expect(controller.sounds, isEmpty);
  });

  test('a limit refusal is shown as a sentence, not a code', () async {
    final repository = FakeExpressionRepository(
      refuseNextUpload: GuildExpressionKind.emoji,
    );
    final controller = _controller(repository);

    final uploaded = await controller.uploadEmoji(
      name: 'one_too_many',
      dataUri: 'data:image/png;base64,QUJD',
    );

    expect(uploaded, isFalse);
    expect(
      controller.actionError,
      isA<GuildExpressionLimitReached>().having(
        (error) => error.message,
        'message',
        'This server has no emoji slots left.',
      ),
    );
    expect(controller.emoji, isEmpty);
  });

  test('every action is gated on the manage-expressions permission', () async {
    final repository = FakeExpressionRepository();
    final controller = _controller(
      repository,
      permissions: DiscordPermissions.manageGuild,
    );

    expect(await controller.uploadEmoji(name: 'x', dataUri: 'data:,'), isFalse);
    expect(
      await controller.uploadSticker(
        name: 'x',
        description: '',
        tags: 'x',
        dataUri: 'data:,',
      ),
      isFalse,
    );
    expect(
      await controller.uploadSound(name: 'x', volume: 1, dataUri: 'data:,'),
      isFalse,
    );
    expect(
      await controller.deleteEmoji(
        const GuildEmoji(id: 'e', spaceId: guildId, name: 'n'),
      ),
      isFalse,
    );
    expect(
      await controller.deleteSticker(
        GuildSticker(
          item: const MessageSticker(
            id: 's',
            name: 'n',
            format: StickerFormat.png,
            url: 'u',
          ),
          spaceId: guildId,
          tags: const [],
          available: true,
        ),
      ),
      isFalse,
    );
    expect(
      await controller.deleteSound(
        const SoundboardSound(id: 'so', name: 'n', guildId: guildId),
      ),
      isFalse,
    );
    expect(repository.calls, isEmpty);
  });
}
