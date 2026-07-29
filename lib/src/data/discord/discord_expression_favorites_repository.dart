import 'dart:async';
import 'dart:developer' as developer;

import '../../domain/expression_favorites.dart';
import '../proto/proto_message.dart';
import 'discord_frecency_proto.dart';
import 'discord_user_settings_patch.dart';
import 'discord_user_settings_proto.dart';
import 'discord_user_settings_transport.dart';

/// The starred GIFs, stickers and emoji of the desktop-user session.
///
/// Unlike the preloaded settings, this blob is not in `READY`: it is fetched
/// the first time a picker wants it and then kept current from dispatches. The
/// decoded root is held rather than only the leaves, because a write replaces
/// the entire blob and the frecency tables living beside these three groups
/// must survive one.
final class DiscordExpressionFavoritesRepository
    implements ExpressionFavoritesRepository {
  DiscordExpressionFavoritesRepository(this._transport);

  static const _type = DiscordSettingsProtoType.frecencyAndFavorites;

  final DiscordUserSettingsTransport _transport;
  final StreamController<ExpressionFavorites> _updates =
      StreamController.broadcast();

  ProtoMessage? _root;
  ExpressionFavorites _current = ExpressionFavorites.empty;
  Future<ExpressionFavorites>? _loadInFlight;
  Future<void>? _writeInFlight;

  @override
  ExpressionFavorites get current => _current;

  @override
  bool get isLoaded => _root != null;

  @override
  Stream<ExpressionFavorites> get updates => _updates.stream;

  @override
  Future<ExpressionFavorites> load() {
    if (_root != null) return Future.value(_current);
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;
    final future = _fetch();
    _loadInFlight = future;
    return future.whenComplete(() => _loadInFlight = null);
  }

  /// Feeds a gateway dispatch to the store.
  ///
  /// A dispatch for the preloaded type is another store's business, so the
  /// type is checked before the blob is touched.
  void acceptGatewayDispatch(String name, Map<String, Object?> data) {
    if (name != 'USER_SETTINGS_PROTO_UPDATE') return;
    final settings = data['settings'];
    if (settings is! Map) return;
    final envelope = settings.cast<String, Object?>();
    if (envelope['type'] != _type) return;
    final blob = envelope['proto'];
    if (blob is! String) return;
    _installBase64(blob, partial: data['partial'] == true);
  }

  @override
  Future<bool> setGifFavorite({
    required FavoriteGif gif,
    required bool favorite,
  }) async {
    final held = await _loaded();
    final kept = [
      for (final existing in held.gifs)
        if (existing.url != gif.url) existing,
    ];
    if (favorite) {
      // Ordered above everything held, which is how Discord numbers them and
      // what puts the newest star at the front of the tab.
      kept.insert(0, _ordered(gif, held.nextGifOrder));
    } else if (kept.length == held.gifs.length) {
      // Nothing was starred under that URL, so there is nothing to unstar and
      // no reason to spend a write proving it.
      return true;
    }
    final next = held.copyWith(
      gifs: kept,
      // Discord stops offering the hint once three GIFs are starred.
      hideGifTooltip: held.hideGifTooltip || kept.length > 2,
    );
    if (favorite && !DiscordFrecencyProtoCodec.fitsGifBudget(next)) {
      return false;
    }
    return _commit(next);
  }

  @override
  Future<bool> setStickerFavorite({
    required String stickerId,
    required bool favorite,
  }) async {
    final held = await _loaded();
    if (favorite && held.isFavoriteSticker(stickerId)) return true;
    if (favorite && !held.canAddSticker) return false;
    return _commit(
      held.copyWith(
        stickerIds: _toggled(held.stickerIds, stickerId, favorite: favorite),
      ),
    );
  }

  @override
  Future<bool> setEmojiFavorite({
    required String idOrName,
    required bool favorite,
  }) async {
    final held = await _loaded();
    if (favorite && held.isFavoriteEmoji(idOrName)) return true;
    if (favorite && !held.canAddEmoji) return false;
    return _commit(
      held.copyWith(
        emojis: _toggled(held.emojis, idOrName, favorite: favorite),
      ),
    );
  }

  Future<void> close() async {
    await _writeInFlight;
    await _updates.close();
  }

  static List<String> _toggled(
    List<String> held,
    String value, {
    required bool favorite,
  }) => favorite
      ? [...held, value]
      : [
          for (final existing in held)
            if (existing != value) existing,
        ];

  static FavoriteGif _ordered(FavoriteGif gif, int order) => FavoriteGif(
    url: gif.url,
    src: gif.src,
    format: gif.format,
    width: gif.width,
    height: gif.height,
    order: order,
  );

  /// The favourites, fetching them first if a picker acted before they loaded.
  ///
  /// Writing against an unfetched blob would send three groups composed from
  /// nothing, which reads on the server as "this account has no favourites"
  /// and erases them.
  Future<ExpressionFavorites> _loaded() async {
    if (_root == null) await load();
    return _current;
  }

  Future<bool> _commit(ExpressionFavorites next) async {
    final root = _root ?? ProtoMessage();
    final composed = DiscordFrecencyProtoCodec.apply(root, next);
    // Shown before the request answers: starring is a click, and a star that
    // waited for a round trip would feel broken on a slow link.
    _install(composed, next);
    final write = _write(composed);
    _writeInFlight = write;
    try {
      return await write;
    } finally {
      if (identical(_writeInFlight, write)) _writeInFlight = null;
    }
  }

  Future<bool> _write(ProtoMessage composed) async {
    try {
      final result = await _transport.writeSettingsProto(
        type: _type,
        settings: DiscordUserSettingsProto.encodeBase64(composed.encode()),
      );
      if (result.outOfDate) {
        _log('Discord rejected a stale favourites write; re-reading');
        await _reload();
        return false;
      }
      final settings = result.settings;
      if (settings != null && settings.isNotEmpty) {
        _installBase64(settings, partial: false);
      }
      return true;
    } on Object catch (error) {
      _log('Saving favourites failed: $error');
      // Put the star back where it was: the optimistic apply promised
      // something the account does not hold.
      await _reload();
      return false;
    }
  }

  Future<void> _reload() async {
    try {
      final blob = await _transport.readSettingsProto(_type);
      if (blob != null && blob.isNotEmpty) {
        _installBase64(blob, partial: false);
        return;
      }
      _install(ProtoMessage(), ExpressionFavorites.empty);
    } on Object catch (error) {
      _log('Re-reading favourites failed: $error');
    }
  }

  Future<ExpressionFavorites> _fetch() async {
    final blob = await _transport.readSettingsProto(_type);
    if (blob == null || blob.isEmpty || !_installBase64(blob, partial: false)) {
      // An account that has starred nothing has no blob at all, which is a
      // valid answer rather than a failure to read one.
      _install(ProtoMessage(), ExpressionFavorites.empty);
    }
    return _current;
  }

  bool _installBase64(String blob, {required bool partial}) {
    final ProtoMessage decoded;
    try {
      decoded = DiscordUserSettingsProto.decodeRoot(blob);
    } on Object catch (error) {
      _log('Discarding undecodable favourites blob: $error');
      return false;
    }
    final root = _root;
    if (partial && root == null) {
      // A partial update carries only what changed; treating it as the whole
      // blob would mark the store loaded while holding a fraction of it, and
      // the next write would send that fraction back as the truth.
      _log('Ignoring a partial favourites update received before the blob');
      return false;
    }
    final next = partial
        ? DiscordUserSettingsPatch.replaceGroups(root!, decoded)
        : decoded;
    _install(next, DiscordFrecencyProtoCodec.decodeMessage(next));
    return true;
  }

  void _install(ProtoMessage root, ExpressionFavorites favorites) {
    _root = root;
    _current = favorites;
    if (!_updates.isClosed) _updates.add(favorites);
  }

  static void _log(String message) =>
      developer.log(message, name: 'flucord.discord.favorites', level: 900);
}
