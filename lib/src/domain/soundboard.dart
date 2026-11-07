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

/// Every sound this session holds: Discord's defaults, and each server's own.
///
/// The servers keep the order they arrived in, which is the order the account
/// lists them in at login.
final class SoundboardCatalogue {
  const SoundboardCatalogue({
    this.defaults = const [],
    this.byGuild = const {},
  });

  final List<SoundboardSound> defaults;
  final Map<String, List<SoundboardSound>> byGuild;

  static const empty = SoundboardCatalogue();

  /// The server's own sounds, then the defaults.
  List<SoundboardSound> soundsFor(String guildId) =>
      List.unmodifiable([...?byGuild[guildId], ...defaults]);

  /// The sound with [soundId], from whichever server holds it.
  SoundboardSound? find(String soundId) {
    for (final sound in [...defaults, ...byGuild.values.expand((s) => s)]) {
      if (sound.id == soundId) return sound;
    }
    return null;
  }

  /// The picker's sections, as Discord orders them: favourites, the server
  /// the call is in, the defaults, then every other server.
  ///
  /// [query] keeps only the sounds whose name holds it, ignoring case. A
  /// section left with no sounds is dropped.
  List<SoundboardSection> sections({
    String? currentGuildId,
    List<String> favoriteIds = const [],
    String query = '',
  }) {
    final needle = query.trim().toLowerCase();
    List<SoundboardSound> matching(Iterable<SoundboardSound> sounds) => [
      for (final sound in sounds)
        if (sound.name.toLowerCase().contains(needle)) sound,
    ];
    final current = currentGuildId;
    return [
      FavoriteSoundsSection(matching(favoriteIds.map(find).nonNulls)),
      if (current != null)
        GuildSoundsSection(current, matching(byGuild[current] ?? const [])),
      DefaultSoundsSection(matching(defaults)),
      for (final MapEntry(key: guildId, value: sounds) in byGuild.entries)
        if (guildId != current) GuildSoundsSection(guildId, matching(sounds)),
    ].where((section) => section.sounds.isNotEmpty).toList(growable: false);
  }
}

/// One group of tiles in the soundboard picker.
sealed class SoundboardSection {
  const SoundboardSection(this.sounds);

  final List<SoundboardSound> sounds;
}

/// The sounds the account starred, from any server.
final class FavoriteSoundsSection extends SoundboardSection {
  const FavoriteSoundsSection(super.sounds);
}

/// One server's own sounds.
final class GuildSoundsSection extends SoundboardSection {
  const GuildSoundsSection(this.guildId, super.sounds);

  final String guildId;
}

/// The sounds everybody has.
final class DefaultSoundsSection extends SoundboardSection {
  const DefaultSoundsSection(super.sounds);
}

/// Which sounds the account may play where it is.
///
/// Without Nitro, Discord allows the defaults and the sounds of the server the
/// call is in. With Nitro, any server's sound plays anywhere, a DM or group
/// call included.
final class SoundboardReach {
  const SoundboardReach({this.guildId, this.everywhere = false});

  /// The server the voice channel belongs to, or null in a DM or group call.
  final String? guildId;

  /// Whether the account's Nitro lets it use any server's sounds.
  final bool everywhere;

  bool allows(SoundboardSound sound) =>
      sound.isDefault || everywhere || sound.guildId == guildId;
}

/// The soundboard sounds this session holds, and the play request.
abstract interface class SoundboardRepository {
  /// Everything held right now. Empty rather than null before anything is
  /// loaded, because a server with no sounds and a server nobody has loaded
  /// yet look the same to the picker.
  SoundboardCatalogue get catalogue;

  /// Fires with a guild id whenever its sounds change.
  Stream<String> get updates;

  /// Fires when anybody plays a sound into a voice channel.
  Stream<SoundboardPlayback> get playbacks;

  /// Reads the defaults if they are not held yet, and [guildId]'s sounds if
  /// it names a server whose sounds are not held. Null reads only the
  /// defaults, which is all a DM call needs to have loaded.
  Future<List<SoundboardSound>> loadSounds(String? guildId);

  /// Plays [sound] into [channelId].
  Future<void> playSound(String channelId, SoundboardSound sound);
}
