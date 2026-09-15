part of 'guild_settings_controller.dart';

extension GuildSettingsControllerExpressions on GuildSettingsController {
  /// Reads the three expression lists the page shows.
  ///
  /// The emoji and stickers come from the expression plane, which also files
  /// them into the local store so the composer's picker picks them up. The
  /// sounds come from the soundboard store, which is also what the picker
  /// reads, so a sound deleted here is gone there without a second request.
  Future<void> _fetchExpressions() async {
    final plane = expressions;
    if (plane != null) {
      _emoji = await plane.loadGuildEmojis(guildId);
      _stickers = await plane.loadGuildStickers(guildId);
    }
    final soundboard = this.soundboard;
    if (soundboard != null) {
      final held = await soundboard.loadSounds(guildId);
      // The defaults belong to everybody and are not this server's to delete,
      // so the page lists only the guild's own sounds.
      _sounds = [
        for (final sound in held)
          if (sound.guildId == guildId) sound,
      ];
    }
  }

  /// Adds one emoji from a `data:` URI the picker produced.
  ///
  /// The name is the only field a person types, so it is the only one the
  /// page takes.
  Future<bool> uploadEmoji({required String name, required String dataUri}) =>
      _runExpression(() async {
        final emoji = await expressions!.uploadGuildEmoji(
          guildId: guildId,
          name: name,
          dataUri: dataUri,
        );
        _emoji = [..._emoji.where((item) => item.id != emoji.id), emoji];
      });

  /// Removes one emoji from the server and from the page.
  Future<bool> deleteEmoji(GuildEmoji emoji) => _runExpression(() async {
    await expressions!.deleteGuildEmoji(guildId: guildId, emojiId: emoji.id);
    _emoji = [
      for (final item in _emoji)
        if (item.id != emoji.id) item,
    ];
  });

  /// Adds one sticker from a `data:` URI the picker produced.
  Future<bool> uploadSticker({
    required String name,
    required String description,
    required String tags,
    required String dataUri,
  }) => _runExpression(() async {
    final sticker = await expressions!.uploadGuildSticker(
      guildId: guildId,
      name: name,
      description: description,
      tags: tags,
      dataUri: dataUri,
    );
    _stickers = [..._stickers.where((item) => item.id != sticker.id), sticker];
  });

  /// Removes one sticker from the server and from the page.
  Future<bool> deleteSticker(GuildSticker sticker) => _runExpression(() async {
    await expressions!.deleteGuildSticker(
      guildId: guildId,
      stickerId: sticker.id,
    );
    _stickers = [
      for (final item in _stickers)
        if (item.id != sticker.id) item,
    ];
  });

  /// Adds one soundboard sound, with the name and volume the form took.
  Future<bool> uploadSound({
    required String name,
    required double volume,
    required String dataUri,
  }) => _runExpression(() async {
    final sound = await expressions!.uploadSoundboardSound(
      guildId: guildId,
      name: name,
      volume: volume,
      dataUri: dataUri,
    );
    _sounds = [..._sounds.where((item) => item.id != sound.id), sound];
  });

  /// Removes one sound from the server and from the page.
  Future<bool> deleteSound(SoundboardSound sound) => _runExpression(() async {
    await expressions!.deleteSoundboardSound(
      guildId: guildId,
      soundId: sound.id,
    );
    _sounds = [
      for (final item in _sounds)
        if (item.id != sound.id) item,
    ];
  });

  /// Runs one expression write behind the window's shared busy flag, with the
  /// permission gate every other write passes. A limit refusal lands in
  /// [actionError] as a sentence rather than a code, the same place every
  /// other failed write explains itself.
  Future<bool> _runExpression(Future<void> Function() action) async {
    if (!_capabilities.canManageExpressions || expressions == null) {
      return false;
    }
    return _run(action);
  }
}
