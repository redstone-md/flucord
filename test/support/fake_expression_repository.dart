import 'dart:async';

import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/guild_expression_errors.dart';
import 'package:flucord/src/domain/guild_expression_repository.dart';
import 'package:flucord/src/domain/soundboard.dart';

/// In-memory stand-ins for the expression routes and the soundboard store,
/// shared by the controller and the widget tests of the expressions page.

/// An in-memory stand-in for the expression routes, recording what the
/// settings window asked for the way the guild-management fake does.
final class FakeExpressionRepository implements GuildExpressionRepository {
  FakeExpressionRepository({this.refuseNextUpload, this.refuseNextDelete});

  /// The numbered reason the next upload answers with, or null to accept.
  final GuildExpressionKind? refuseNextUpload;

  /// The numbered reason the next delete answers with, or null to accept.
  final GuildExpressionKind? refuseNextDelete;

  final List<String> calls = [];
  final List<({String kind, String name, String dataUri})> uploads = [];
  final List<({String kind, String id})> deletes = [];
  final Map<String, List<GuildEmoji>> emojiByGuild = {};
  final Map<String, List<GuildSticker>> stickersByGuild = {};
  int _nextId = 0;

  void _record(String call) => calls.add(call);

  @override
  Future<List<GuildEmoji>> loadGuildEmojis(String guildId) async {
    _record('loadGuildEmojis');
    return emojiByGuild[guildId] ?? const [];
  }

  @override
  Future<GuildEmoji> uploadGuildEmoji({
    required String guildId,
    required String name,
    required String dataUri,
  }) async {
    _record('uploadGuildEmoji');
    if (refuseNextUpload != null) {
      throw GuildExpressionLimitReached(refuseNextUpload!);
    }
    uploads.add((kind: 'emoji', name: name, dataUri: dataUri));
    final emoji = GuildEmoji(
      id: 'emoji-${_nextId++}',
      spaceId: guildId,
      name: name,
    );
    emojiByGuild[guildId] = [...?emojiByGuild[guildId], emoji];
    return emoji;
  }

  @override
  Future<void> deleteGuildEmoji({
    required String guildId,
    required String emojiId,
  }) async {
    _record('deleteGuildEmoji');
    if (refuseNextDelete != null) {
      throw GuildExpressionLimitReached(refuseNextDelete!);
    }
    deletes.add((kind: 'emoji', id: emojiId));
    emojiByGuild[guildId] = [
      ...?emojiByGuild[guildId]?.where((item) => item.id != emojiId),
    ];
  }

  @override
  Future<List<GuildSticker>> loadGuildStickers(String guildId) async {
    _record('loadGuildStickers');
    return stickersByGuild[guildId] ?? const [];
  }

  @override
  Future<GuildSticker> uploadGuildSticker({
    required String guildId,
    required String name,
    required String description,
    required String tags,
    required String dataUri,
  }) async {
    _record('uploadGuildSticker');
    if (refuseNextUpload != null) {
      throw GuildExpressionLimitReached(refuseNextUpload!);
    }
    uploads.add((kind: 'sticker', name: name, dataUri: dataUri));
    final sticker = GuildSticker(
      item: MessageSticker(
        id: 'sticker-${_nextId++}',
        name: name,
        format: StickerFormat.png,
        url: 'https://cdn.discordapp.com/stickers/1.png',
      ),
      spaceId: guildId,
      description: description,
      tags: [tags],
      available: true,
    );
    stickersByGuild[guildId] = [...?stickersByGuild[guildId], sticker];
    return sticker;
  }

  @override
  Future<void> deleteGuildSticker({
    required String guildId,
    required String stickerId,
  }) async {
    _record('deleteGuildSticker');
    if (refuseNextDelete != null) {
      throw GuildExpressionLimitReached(refuseNextDelete!);
    }
    deletes.add((kind: 'sticker', id: stickerId));
    stickersByGuild[guildId] = [
      ...?stickersByGuild[guildId]?.where((item) => item.id != stickerId),
    ];
  }

  @override
  Future<SoundboardSound> uploadSoundboardSound({
    required String guildId,
    required String name,
    required double volume,
    required String dataUri,
  }) async {
    _record('uploadSoundboardSound');
    if (refuseNextUpload != null) {
      throw GuildExpressionLimitReached(refuseNextUpload!);
    }
    uploads.add((kind: 'sound', name: name, dataUri: dataUri));
    final sound = SoundboardSound(
      id: 'sound-${_nextId++}',
      name: name,
      guildId: guildId,
      volume: volume,
    );
    soundsByGuild[guildId] = [...?soundsByGuild[guildId], sound];
    return sound;
  }

  @override
  Future<void> deleteSoundboardSound({
    required String guildId,
    required String soundId,
  }) async {
    _record('deleteSoundboardSound');
    if (refuseNextDelete != null) {
      throw GuildExpressionLimitReached(refuseNextDelete!);
    }
    deletes.add((kind: 'sound', id: soundId));
    soundsByGuild[guildId] = [
      ...?soundsByGuild[guildId]?.where((item) => item.id != soundId),
    ];
  }

  final Map<String, List<SoundboardSound>> soundsByGuild = {};
}

/// The soundboard store the page lists sounds from.
final class FakeSoundboardRepository implements SoundboardRepository {
  final StreamController<String> _updates = StreamController.broadcast();
  final StreamController<SoundboardPlayback> _playbacks =
      StreamController.broadcast();
  final Map<String, List<SoundboardSound>> byGuild = {};

  @override
  List<SoundboardSound> soundsFor(String guildId) =>
      byGuild[guildId] ?? const [];

  @override
  Stream<String> get updates => _updates.stream;

  @override
  Stream<SoundboardPlayback> get playbacks => _playbacks.stream;

  @override
  Future<List<SoundboardSound>> loadSounds(String guildId) async =>
      byGuild[guildId] ?? const [];

  @override
  Future<void> playSound(String channelId, SoundboardSound sound) async {}

  Future<void> close() async {
    await _updates.close();
    await _playbacks.close();
  }
}
