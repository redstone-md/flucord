/// One soundboard sound, as Discord serves both kinds of them.
///
/// Discord has two sources with the same shape: a fixed set everybody has, and
/// per-server sounds. They differ only in whether a guild owns them, which is
/// what decides whether `source_guild_id` goes out with the play request.
final class SoundboardSound {
  const SoundboardSound({
    required this.id,
    required this.name,
    this.guildId,
    this.emojiId,
    this.emojiName,
    this.volume = 1,
    this.isAvailable = true,
  });

  final String id;
  final String name;

  /// Null for a default sound, which belongs to nobody.
  final String? guildId;

  final String? emojiId;
  final String? emojiName;

  /// `0`–`1`, as the server stores it.
  final double volume;

  /// False when the server lost the boost level that paid for the sound.
  /// Discord keeps showing it, greyed out, rather than hiding what was there.
  final bool isAvailable;

  bool get isDefault => guildId == null;

  /// The CDN object this sound plays from.
  String get url => 'https://cdn.discordapp.com/soundboard-sounds/$id';

  @override
  bool operator ==(Object other) =>
      other is SoundboardSound &&
      other.id == id &&
      other.name == name &&
      other.guildId == guildId &&
      other.emojiId == emojiId &&
      other.emojiName == emojiName &&
      other.volume == volume &&
      other.isAvailable == isAvailable;

  @override
  int get hashCode =>
      Object.hash(id, name, guildId, emojiId, emojiName, volume, isAvailable);
}

/// Somebody playing a sound into a voice channel.
final class SoundboardPlayback {
  const SoundboardPlayback({
    required this.channelId,
    required this.userId,
    required this.soundId,
    this.guildId,
  });

  final String channelId;
  final String userId;
  final String soundId;

  /// Which server's sound was played, or null for a default one.
  final String? guildId;
}

/// The soundboard of whichever server is on screen.
abstract interface class SoundboardRepository {
  /// Sounds playable in [guildId]: the server's own, then the defaults.
  ///
  /// Empty before anything is loaded rather than null, because a server with
  /// no sounds of its own and a server nobody has loaded yet look the same to
  /// the picker and neither should make it disappear.
  List<SoundboardSound> soundsFor(String guildId);

  /// Fires with a guild id whenever its sounds change.
  Stream<String> get updates;

  /// Fires when anybody plays a sound into a voice channel.
  Stream<SoundboardPlayback> get playbacks;

  /// Reads the server's sounds, and the defaults if they are not held yet.
  Future<List<SoundboardSound>> loadSounds(String guildId);

  /// Plays [sound] into [channelId].
  Future<void> playSound(String channelId, SoundboardSound sound);
}
