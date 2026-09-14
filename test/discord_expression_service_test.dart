import 'dart:convert';

import 'package:flucord/src/data/discord/discord_expression_service.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/data/discord/discord_multipart_body.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/discord/discord_soundboard_service.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/guild_expression_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _guildId = '111111111111111111';

/// A stand-in for the REST session, recording each call the way the queue
/// transport of the guild-management tests does.
final class _FakeTransport implements DiscordExpressionTransport {
  _FakeTransport({this.emojiLimitReached = false});

  final bool emojiLimitReached;
  final List<({String method, String path, Object? body})> calls = [];
  List<Map<String, Object?>> emojiPayloads = const [];

  @override
  Future<List<Map<String, Object?>>> listGuildEmojis(String guildId) async {
    calls.add((method: 'GET', path: '/guilds/$guildId/emojis', body: null));
    return emojiPayloads;
  }

  @override
  Future<Map<String, Object?>> createGuildEmoji(
    String guildId,
    Map<String, Object?> body,
  ) async {
    calls.add((
      method: 'POST',
      path: '/guilds/$guildId/emojis',
      body: Map<String, Object?>.of(body),
    ));
    if (emojiLimitReached) {
      throw const DiscordApiException(
        statusCode: 400,
        message: 'Maximum number of emojis reached',
        responsePayload: {'code': 30008, 'message': 'Maximum number reached'},
      );
    }
    return {
      'id': 'emoji-new',
      'name': body['name'],
      'animated': false,
      'available': true,
    };
  }

  @override
  Future<void> deleteGuildEmoji(String guildId, String emojiId) async {
    calls.add((
      method: 'DELETE',
      path: '/guilds/$guildId/emojis/$emojiId',
      body: null,
    ));
  }

  @override
  Future<List<Map<String, Object?>>> listGuildStickers(String guildId) async {
    calls.add((method: 'GET', path: '/guilds/$guildId/stickers', body: null));
    return const [];
  }

  @override
  Future<Map<String, Object?>> createGuildSticker(
    String guildId,
    DiscordMultipartBody body,
  ) async {
    calls.add((
      method: 'POST',
      path: '/guilds/$guildId/stickers',
      body: utf8.decode(body.bytes),
    ));
    return {
      'id': 'sticker-new',
      'name': 'seal',
      'format_type': 1,
      'description': 'A seal claps.',
      'tags': 'seal',
      'available': true,
    };
  }

  @override
  Future<void> deleteGuildSticker(String guildId, String stickerId) async {
    calls.add((
      method: 'DELETE',
      path: '/guilds/$guildId/stickers/$stickerId',
      body: null,
    ));
  }

  @override
  Future<Map<String, Object?>> createSoundboardSound(
    String guildId,
    Map<String, Object?> body,
  ) async {
    calls.add((
      method: 'POST',
      path: '/guilds/$guildId/soundboard-sounds',
      body: Map<String, Object?>.of(body),
    ));
    return {
      'sound_id': 'sound-new',
      'name': body['name'],
      'volume': body['volume'],
      'available': true,
    };
  }

  @override
  Future<void> deleteSoundboardSound(String guildId, String soundId) async {
    calls.add((
      method: 'DELETE',
      path: '/guilds/$guildId/soundboard-sounds/$soundId',
      body: null,
    ));
  }
}

final class _UnusedSoundboardTransport implements DiscordSoundboardTransport {
  @override
  Future<List<Map<String, Object?>>> listDefaultSounds() async => const [];

  @override
  Future<Map<String, Object?>> listGuildSounds(String guildId) async => {
    'items': const <Object?>[],
  };

  @override
  Future<void> sendSoundboardSound(
    String channelId, {
    required String soundId,
    String? emojiId,
    String? emojiName,
    String? sourceGuildId,
  }) async {}
}

/// The store only reads back once a workspace exists, so every test writes
/// the minimum one first.
Future<SqliteChatCache> _openCache() async {
  final cache = await SqliteChatCache.openAt(
    inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  await cache.writeWorkspace(
    ChatWorkspace(
      spaces: const [
        CommunitySpace(
          id: _guildId,
          name: 'Forge',
          monogram: 'FO',
          colorValue: 0xff456b5a,
        ),
      ],
      channels: const [
        ConversationChannel(
          id: '222222222222222222',
          spaceId: _guildId,
          name: 'general',
          topic: '',
          kind: ChannelKind.text,
        ),
      ],
      members: const [],
      messages: const [],
      currentMemberId: '333333333333333333',
    ),
  );
  return cache;
}

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'the emoji upload reaches the documented route and folds into the store',
    () async {
      final cache = await _openCache();
      addTearDown(cache.close);
      final soundboard = DiscordSoundboardService(_UnusedSoundboardTransport());
      addTearDown(soundboard.close);
      final transport = _FakeTransport();
      final service = DiscordExpressionService(
        transport,
        cache,
        DiscordMapper(),
        soundboard: soundboard,
      );

      final emoji = await service.uploadGuildEmoji(
        guildId: _guildId,
        name: 'forge_spark',
        dataUri: 'data:image/png;base64,QUJD',
      );

      expect(emoji.messageSyntax, '<:forge_spark:emoji-new>');
      final call = transport.calls.single;
      expect(call.method, 'POST');
      expect(call.path, '/guilds/$_guildId/emojis');
      expect(call.body, {
        'name': 'forge_spark',
        'image': 'data:image/png;base64,QUJD',
      });
      // The picker reads the workspace, which is restored from this store.
      final stored = await cache.readWorkspace();
      expect(stored?.emojis.single.id, 'emoji-new');
    },
  );

  test('a limit refusal is translated into the plain sentence', () async {
    final cache = await _openCache();
    addTearDown(cache.close);
    final service = DiscordExpressionService(
      _FakeTransport(emojiLimitReached: true),
      cache,
      DiscordMapper(),
    );

    await expectLater(
      service.uploadGuildEmoji(
        guildId: _guildId,
        name: 'one_too_many',
        dataUri: 'data:image/png;base64,QUJD',
      ),
      throwsA(
        isA<GuildExpressionLimitReached>().having(
          (error) => error.message,
          'message',
          'This server has no emoji slots left.',
        ),
      ),
    );
    // Nothing was stored for a refused upload: the store still holds the
    // seeded workspace and no emoji.
    final stored = await cache.readWorkspace();
    expect(stored?.emojis, isEmpty);
  });

  test(
    'a sticker upload sends a multipart form and folds into the store',
    () async {
      final cache = await _openCache();
      addTearDown(cache.close);
      final transport = _FakeTransport();
      final service = DiscordExpressionService(
        transport,
        cache,
        DiscordMapper(),
      );

      final sticker = await service.uploadGuildSticker(
        guildId: _guildId,
        name: 'seal',
        description: 'A seal claps.',
        tags: 'seal',
        dataUri: 'data:image/png;base64,QUJD',
      );

      expect(sticker.id, 'sticker-new');
      final form = transport.calls.single.body! as String;
      // The three fields travel as form parts, and the file part carries the
      // decoded bytes under the name the route reads.
      expect(form, contains('name="name"'));
      expect(form, contains('name="description"'));
      expect(form, contains('name="tags"'));
      expect(form, contains('name="file"; filename="sticker.png"'));
      final stored = await cache.readWorkspace();
      expect(stored?.stickers.single.id, 'sticker-new');
    },
  );

  test(
    'a sound upload folds into the soundboard store the picker reads',
    () async {
      final cache = await _openCache();
      addTearDown(cache.close);
      final soundboard = DiscordSoundboardService(_UnusedSoundboardTransport());
      addTearDown(soundboard.close);
      final service = DiscordExpressionService(
        _FakeTransport(),
        cache,
        DiscordMapper(),
        soundboard: soundboard,
      );

      final sound = await service.uploadSoundboardSound(
        guildId: _guildId,
        name: 'airhorn',
        volume: 0.4,
        dataUri: 'data:audio/mpeg;base64,QUJD',
      );

      expect(sound.id, 'sound-new');
      expect(soundboard.soundsFor(_guildId).single.id, 'sound-new');
      expect(soundboard.soundsFor(_guildId).single.volume, 0.4);
    },
  );

  test('a change announces the fresh set the workspace folds', () async {
    final cache = await _openCache();
    addTearDown(cache.close);
    final published = <ChatRepositoryEvent>[];
    final service = DiscordExpressionService(
      _FakeTransport(),
      cache,
      DiscordMapper(),
      publish: published.add,
    );

    await service.uploadGuildEmoji(
      guildId: _guildId,
      name: 'forge_spark',
      dataUri: 'data:image/png;base64,QUJD',
    );

    final event = published.single as GuildEmojisReplacedEvent;
    expect(event.spaceId, _guildId);
    // The announced set is the whole guild set, which is the shape the
    // workspace's replace fold expects.
    expect(event.emojis.single.messageSyntax, '<:forge_spark:emoji-new>');
  });

  test('deletes remove the expression from the stores', () async {
    final cache = await _openCache();
    addTearDown(cache.close);
    final soundboard = DiscordSoundboardService(_UnusedSoundboardTransport());
    addTearDown(soundboard.close);
    final transport = _FakeTransport();
    final service = DiscordExpressionService(
      transport,
      cache,
      DiscordMapper(),
      soundboard: soundboard,
    );

    await service.uploadGuildEmoji(
      guildId: _guildId,
      name: 'forge_spark',
      dataUri: 'data:image/png;base64,QUJD',
    );
    await service.uploadSoundboardSound(
      guildId: _guildId,
      name: 'airhorn',
      volume: 1,
      dataUri: 'data:audio/mpeg;base64,QUJD',
    );

    await service.deleteGuildEmoji(guildId: _guildId, emojiId: 'emoji-new');
    await service.deleteSoundboardSound(
      guildId: _guildId,
      soundId: 'sound-new',
    );

    expect((await cache.readWorkspace())?.emojis, isEmpty);
    expect(soundboard.soundsFor(_guildId), isEmpty);
    expect(
      transport.calls.map((call) => '${call.method} ${call.path}'),
      containsAllInOrder(const [
        'POST /guilds/$_guildId/emojis',
        'POST /guilds/$_guildId/soundboard-sounds',
        'DELETE /guilds/$_guildId/emojis/emoji-new',
        'DELETE /guilds/$_guildId/soundboard-sounds/sound-new',
      ]),
    );
  });
}
