import 'dart:typed_data';

import '../../domain/expression_favorites.dart';
import '../proto/proto_message.dart';

/// Field numbers inside `FrecencyUserSettings`, the type 2 blob.
abstract final class FrecencyUserSettingsField {
  static const versions = 1;
  static const favoriteGifs = 2;
  static const favoriteStickers = 3;
  static const stickerFrecency = 4;
  static const favoriteEmojis = 5;
  static const emojiFrecency = 6;
}

abstract final class FavoriteGifsField {
  /// `map<string, FavoriteGIF>` — repeated entries, not one value.
  static const gifs = 1;
  static const hideTooltip = 2;
}

abstract final class FavoriteGifField {
  static const format = 1;
  static const src = 2;
  static const width = 3;
  static const height = 4;
  static const order = 5;
}

abstract final class FavoriteStickersField {
  /// `repeated fixed64` — snowflakes, written packed.
  static const stickerIds = 1;
}

abstract final class FavoriteEmojisField {
  static const emojis = 1;
}

/// The two halves of a protobuf map entry.
abstract final class ProtoMapEntryField {
  static const key = 1;
  static const value = 2;
}

/// Reads and writes the favourites held in `FrecencyUserSettings`.
///
/// Only the three groups the pickers draw are modelled. Everything else — the
/// frecency tables, soundboard sounds, the command histories — is left in the
/// buffer untouched, because a write replaces the whole blob and a codec that
/// dropped what it did not understand would wipe those groups off the account
/// on the first starred GIF.
abstract final class DiscordFrecencyProtoCodec {
  static ExpressionFavorites decode(Uint8List bytes) =>
      decodeMessage(ProtoMessage.decode(bytes));

  static ExpressionFavorites decodeMessage(ProtoMessage root) {
    final gifsGroup = root.messageAt(FrecencyUserSettingsField.favoriteGifs);
    final stickers = root.messageAt(
      FrecencyUserSettingsField.favoriteStickers,
    );
    final emojis = root.messageAt(FrecencyUserSettingsField.favoriteEmojis);
    return ExpressionFavorites(
      gifs: _decodeGifs(gifsGroup),
      hideGifTooltip: gifsGroup?.boolAt(FavoriteGifsField.hideTooltip) ?? false,
      stickerIds: [
        for (final id in stickers?.fixed64ListAt(
              FavoriteStickersField.stickerIds,
            ) ??
            const <int>[])
          _snowflakeOf(id),
      ],
      emojis: emojis?.stringsAt(FavoriteEmojisField.emojis) ?? const [],
    );
  }

  /// Writes [favorites] into a copy of [root], leaving every other group as it
  /// arrived.
  static ProtoMessage apply(ProtoMessage root, ExpressionFavorites favorites) {
    final next = root.clone()
      ..setMessage(
        FrecencyUserSettingsField.favoriteGifs,
        _encodeGifs(favorites),
      )
      ..setMessage(
        FrecencyUserSettingsField.favoriteStickers,
        ProtoMessage()
          ..setFixed64List(FavoriteStickersField.stickerIds, [
            for (final id in favorites.stickerIds)
              if (int.tryParse(id) case final int value) value,
          ]),
      )
      ..setMessage(
        FrecencyUserSettingsField.favoriteEmojis,
        ProtoMessage()
          ..setStrings(FavoriteEmojisField.emojis, favorites.emojis),
      );
    return next;
  }

  /// Whether the GIF group would still fit once written.
  ///
  /// Discord caps this one by encoded weight rather than by count, so the only
  /// way to answer is to encode it.
  static bool fitsGifBudget(ExpressionFavorites favorites) =>
      _encodeGifs(favorites).encode().length <= favoriteGifsMaxBytes;

  static List<FavoriteGif> _decodeGifs(ProtoMessage? group) {
    if (group == null) return const [];
    final gifs = <FavoriteGif>[];
    for (final entry in group.messagesAt(FavoriteGifsField.gifs)) {
      final url = entry.stringAt(ProtoMapEntryField.key);
      final value = entry.messageAt(ProtoMapEntryField.value);
      if (url == null || value == null) continue;
      gifs.add(
        FavoriteGif(
          url: url,
          // A GIF whose entry carried no source still plays from its key,
          // which is a URL in its own right.
          src: value.stringAt(FavoriteGifField.src) ?? url,
          format: FavoriteGifFormat.fromCode(
            value.varintAt(FavoriteGifField.format),
          ),
          width: value.varintAt(FavoriteGifField.width) ?? 0,
          height: value.varintAt(FavoriteGifField.height) ?? 0,
          order: value.varintAt(FavoriteGifField.order) ?? 0,
        ),
      );
    }
    // Highest order first: Discord numbers upwards as GIFs are starred, so
    // this is newest first.
    gifs.sort((a, b) => b.order.compareTo(a.order));
    return gifs;
  }

  static ProtoMessage _encodeGifs(ExpressionFavorites favorites) {
    final group = ProtoMessage();
    for (final gif in favorites.gifs) {
      group.addMessage(
        FavoriteGifsField.gifs,
        ProtoMessage()
          ..setString(ProtoMapEntryField.key, gif.url)
          ..setMessage(
            ProtoMapEntryField.value,
            ProtoMessage()
              ..setVarint(FavoriteGifField.format, gif.format.code)
              ..setString(FavoriteGifField.src, gif.src)
              ..setVarint(FavoriteGifField.width, gif.width)
              ..setVarint(FavoriteGifField.height, gif.height)
              ..setVarint(FavoriteGifField.order, gif.order),
          ),
      );
    }
    if (favorites.hideGifTooltip) {
      group.setBool(FavoriteGifsField.hideTooltip, true);
    }
    return group;
  }

  /// A snowflake as text, reading the sixty-four bits unsigned.
  ///
  /// Dart's `int` is signed, so an id past 2^63 — which Discord has not minted
  /// yet, but the field width allows — would otherwise come back negative.
  static String _snowflakeOf(int value) {
    if (value >= 0) return '$value';
    return (BigInt.from(value) + (BigInt.one << 64)).toString();
  }
}
