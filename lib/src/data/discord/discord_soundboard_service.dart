import 'dart:async';

import '../../domain/soundboard.dart';

/// The REST surface the soundboard needs.
abstract interface class DiscordSoundboardTransport {
  /// `GET /soundboard-default-sounds`.
  Future<List<Map<String, Object?>>> listDefaultSounds();

  /// `GET /guilds/{id}/soundboard-sounds`.
  Future<Map<String, Object?>> listGuildSounds(String guildId);

  /// `POST /channels/{id}/send-soundboard-sound`.
  Future<void> sendSoundboardSound(
    String channelId, {
    required String soundId,
    String? emojiId,
    String? emojiName,
    String? sourceGuildId,
  });
}

/// Soundboard sounds and the effects other people send.
final class DiscordSoundboardService implements SoundboardRepository {
  DiscordSoundboardService(this._transport);

  final DiscordSoundboardTransport _transport;
  final StreamController<String> _updates = StreamController.broadcast();
  final StreamController<SoundboardPlayback> _playbacks =
      StreamController.broadcast();
  final Map<String, List<SoundboardSound>> _byGuild = {};

  List<SoundboardSound> _defaults = const [];

  @override
  List<SoundboardSound> soundsFor(String guildId) =>
      List.unmodifiable([...?_byGuild[guildId], ..._defaults]);

  @override
  Stream<String> get updates => _updates.stream;

  @override
  Stream<SoundboardPlayback> get playbacks => _playbacks.stream;

  @override
  Future<List<SoundboardSound>> loadSounds(String guildId) async {
    // The defaults never change within a session, so they are read once and
    // shared by every server rather than fetched per picker opening.
    if (_defaults.isEmpty) {
      _defaults = _readSounds(await _transport.listDefaultSounds(), null);
    }
    final payload = await _transport.listGuildSounds(guildId);
    _byGuild[guildId] = _readSounds(_objects(payload['items']), guildId);
    _publish(guildId);
    return soundsFor(guildId);
  }

  @override
  Future<void> playSound(String channelId, SoundboardSound sound) =>
      _transport.sendSoundboardSound(
        channelId,
        soundId: sound.id,
        emojiId: sound.emojiId,
        emojiName: sound.emojiName,
        // Only a server's own sound names where it came from. Sending a guild
        // id for a default sound is what Discord answers with 400.
        sourceGuildId: sound.guildId,
      );

  /// Folds a gateway dispatch into the store.
  ///
  /// Returns the guild whose sounds changed, or `null` for anything else.
  String? accept(String eventName, Map<String, Object?> data) =>
      switch (eventName) {
        'GUILD_SOUNDBOARD_SOUND_CREATE' ||
        'GUILD_SOUNDBOARD_SOUND_UPDATE' => _upsert(data),
        'GUILD_SOUNDBOARD_SOUND_DELETE' => _remove(data),
        'GUILD_SOUNDBOARD_SOUNDS_UPDATE' => _replace(data),
        'VOICE_CHANNEL_EFFECT_SEND' => _acceptEffect(data),
        _ => null,
      };

  Future<void> close() async {
    if (!_updates.isClosed) await _updates.close();
    if (!_playbacks.isClosed) await _playbacks.close();
  }

  String? _upsert(Map<String, Object?> data) {
    final guildId = data['guild_id'];
    if (guildId is! String || guildId.isEmpty) return null;
    final sound = readSound(data, guildId);
    if (sound == null) return null;
    _byGuild[guildId] = [
      ...?_byGuild[guildId]?.where((existing) => existing.id != sound.id),
      sound,
    ];
    return _publish(guildId);
  }

  String? _remove(Map<String, Object?> data) {
    final guildId = data['guild_id'];
    final soundId = data['sound_id'];
    if (guildId is! String || soundId is! String) return null;
    final existing = _byGuild[guildId];
    if (existing == null) return null;
    _byGuild[guildId] = existing
        .where((sound) => sound.id != soundId)
        .toList(growable: false);
    return _publish(guildId);
  }

  String? _replace(Map<String, Object?> data) {
    final guildId = data['guild_id'];
    if (guildId is! String || guildId.isEmpty) return null;
    _byGuild[guildId] = _readSounds(
      _objects(data['soundboard_sounds']),
      guildId,
    );
    return _publish(guildId);
  }

  /// `VOICE_CHANNEL_EFFECT_SEND` also carries emoji reactions, which have no
  /// sound id; only the soundboard half is reported here.
  String? _acceptEffect(Map<String, Object?> data) {
    final soundId = data['sound_id'];
    final channelId = data['channel_id'];
    final userId = data['user_id'];
    if (channelId is! String || userId is! String) return null;
    final id = soundId is String
        ? soundId
        : soundId is int
        ? '$soundId'
        : null;
    if (id == null) return null;
    final guildId = data['guild_id'];
    if (!_playbacks.isClosed) {
      _playbacks.add(
        SoundboardPlayback(
          channelId: channelId,
          userId: userId,
          soundId: id,
          guildId: guildId is String && guildId.isNotEmpty ? guildId : null,
        ),
      );
    }
    return guildId is String ? guildId : null;
  }

  String _publish(String guildId) {
    if (!_updates.isClosed) _updates.add(guildId);
    return guildId;
  }

  List<SoundboardSound> _readSounds(
    List<Map<String, Object?>> payload,
    String? guildId,
  ) => [for (final raw in payload) ?readSound(raw, guildId)];

  /// Maps a sound, skipping one with no id.
  ///
  /// Discord sends the id as a string for a guild sound and as a number for a
  /// default one, which is why both are accepted rather than one being assumed.
  static SoundboardSound? readSound(
    Map<String, Object?> payload,
    String? guildId,
  ) {
    final raw = payload['sound_id'] ?? payload['id'];
    final id = raw is String && raw.isNotEmpty
        ? raw
        : raw is int
        ? '$raw'
        : null;
    if (id == null) return null;
    final owner = payload['guild_id'];
    return SoundboardSound(
      id: id,
      name: payload['name'] is String ? payload['name']! as String : '',
      guildId: owner is String && owner.isNotEmpty ? owner : guildId,
      emojiId: payload['emoji_id'] is String
          ? payload['emoji_id']! as String
          : null,
      emojiName: payload['emoji_name'] is String
          ? payload['emoji_name']! as String
          : null,
      volume: switch (payload['volume']) {
        final double value => value,
        final int value => value.toDouble(),
        _ => 1,
      },
      isAvailable: payload['available'] != false,
    );
  }

  static List<Map<String, Object?>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((entry) => entry.cast<String, Object?>())
            .toList(growable: false)
      : const [];
}
