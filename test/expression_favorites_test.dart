import 'dart:convert';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_expression_favorites_repository.dart';
import 'package:flucord/src/data/discord/discord_frecency_proto.dart';
import 'package:flucord/src/data/discord/discord_user_settings_transport.dart';
import 'package:flucord/src/data/proto/proto_message.dart';
import 'package:flucord/src/domain/expression_favorites.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what the blob says', () {
    test('a starred GIF, sticker and emoji all come back', () {
      final blob = _blob(
        gifs: {
          'https://tenor.example/one.gif': _gifEntry(
            src: 'https://cdn.example/one.gif',
            format: 1,
            width: 320,
            height: 180,
            order: 1,
          ),
        },
        stickerIds: [111],
        emojis: ['grinning', '900000000000000000'],
        hideTooltip: true,
      );

      final favorites = DiscordFrecencyProtoCodec.decode(blob);

      expect(favorites.gifs.single.url, 'https://tenor.example/one.gif');
      expect(favorites.gifs.single.src, 'https://cdn.example/one.gif');
      expect(favorites.gifs.single.format, FavoriteGifFormat.image);
      expect(favorites.gifs.single.aspectRatio, closeTo(320 / 180, 0.001));
      expect(favorites.stickerIds, ['111']);
      expect(favorites.emojis, ['grinning', '900000000000000000']);
      expect(favorites.hideGifTooltip, isTrue);
      expect(favorites.isEmpty, isFalse);
    });

    test('the newest star is first', () {
      final blob = _blob(
        gifs: {
          'a': _gifEntry(order: 1),
          'c': _gifEntry(order: 3),
          'b': _gifEntry(order: 2),
        },
      );

      final gifs = DiscordFrecencyProtoCodec.decode(blob).gifs;

      // Discord numbers upwards as they are starred, so the highest is newest.
      expect(gifs.map((gif) => gif.url), ['c', 'b', 'a']);
    });

    test('an entry that carried no source plays from its key', () {
      final blob = _blob(gifs: {'https://tenor.example/x.gif': ProtoMessage()});

      final gif = DiscordFrecencyProtoCodec.decode(blob).gifs.single;

      expect(gif.src, 'https://tenor.example/x.gif');
      expect(gif.format, FavoriteGifFormat.none);
      expect(gif.aspectRatio, isNull);
    });

    test('a format a newer client wrote reads as none rather than throwing', () {
      final blob = _blob(gifs: {'a': _gifEntry(format: 7)});

      expect(
        DiscordFrecencyProtoCodec.decode(blob).gifs.single.format,
        FavoriteGifFormat.none,
      );
    });

    test('a half-written map entry is skipped', () {
      final group = ProtoMessage()
        // A key with no value, and a value with no key: neither names a GIF.
        ..addMessage(FavoriteGifsField.gifs, ProtoMessage()..setString(1, 'a'))
        ..addMessage(
          FavoriteGifsField.gifs,
          ProtoMessage()..setMessage(2, ProtoMessage()),
        );
      final root = ProtoMessage()
        ..setMessage(FrecencyUserSettingsField.favoriteGifs, group);

      expect(DiscordFrecencyProtoCodec.decodeMessage(root).gifs, isEmpty);
    });

    test('an account that starred nothing decodes to nothing', () {
      final favorites = DiscordFrecencyProtoCodec.decode(Uint8List(0));

      expect(favorites.isEmpty, isTrue);
      expect(favorites.hideGifTooltip, isFalse);
    });

    test('sticker ids are read whether packed or not', () {
      final packed = ProtoMessage()
        ..setFixed64List(FavoriteStickersField.stickerIds, [7, 8]);
      final loose = ProtoMessage()
        ..addField(ProtoField(FavoriteStickersField.stickerIds, ProtoFixed64(9)))
        ..addField(
          ProtoField(FavoriteStickersField.stickerIds, ProtoFixed64(10)),
        )
        // A varint under the same number is not a sticker id at all.
        ..addField(ProtoField(FavoriteStickersField.stickerIds, ProtoVarint(3)));

      expect(packed.fixed64ListAt(FavoriteStickersField.stickerIds), [7, 8]);
      expect(loose.fixed64ListAt(FavoriteStickersField.stickerIds), [9, 10]);
    });

    test('an id past the signed range still reads as its own number', () {
      final root = ProtoMessage()
        ..setMessage(
          FrecencyUserSettingsField.favoriteStickers,
          ProtoMessage()..setFixed64List(FavoriteStickersField.stickerIds, [-1]),
        );

      expect(DiscordFrecencyProtoCodec.decodeMessage(root).stickerIds, [
        '18446744073709551615',
      ]);
    });

    test('an empty list clears the field rather than writing an empty one', () {
      final message = ProtoMessage()
        ..setFixed64List(1, [1])
        ..setFixed64List(1, const []);

      expect(message.isEmpty, isTrue);
    });

    test('a media type names the format', () {
      expect(
        FavoriteGifFormat.fromMediaType('video/mp4'),
        FavoriteGifFormat.video,
      );
      expect(
        FavoriteGifFormat.fromMediaType('WEBM'),
        FavoriteGifFormat.video,
      );
      expect(FavoriteGifFormat.fromMediaType('gif'), FavoriteGifFormat.image);
      expect(FavoriteGifFormat.fromMediaType(''), FavoriteGifFormat.none);
    });
  });



  group('how often each was used', () {
    test('the frecency tables are read, keyed the way each one writes it', () {
      final root = ProtoMessage()
        ..setMessage(
          FrecencyUserSettingsField.stickerFrecency,
          ProtoMessage()
            ..addMessage(
              1,
              ProtoMessage()
                ..setFixed64(ProtoMapEntryField.key, 55)
                ..setMessage(
                  ProtoMapEntryField.value,
                  ProtoMessage()
                    ..setVarint(FrecencyItemField.totalUses, 9)
                    ..setVarint(FrecencyItemField.score, 40)
                    ..setFixed64List(FrecencyItemField.recentUses, [1, 2, 3]),
                ),
            ),
        )
        ..setMessage(
          FrecencyUserSettingsField.emojiFrecency,
          ProtoMessage()
            ..addMessage(
              1,
              ProtoMessage()
                ..setString(ProtoMapEntryField.key, 'grinning')
                // Only `frecency` filled: another client may write one of the
                // two and not the other.
                ..setMessage(
                  ProtoMapEntryField.value,
                  ProtoMessage()..setVarint(FrecencyItemField.frecency, 7),
                ),
            ),
        );

      final read = DiscordFrecencyProtoCodec.decodeMessage(root);

      final sticker = read.stickerFrecency.scoreFor('55')!;
      expect(sticker.totalUses, 9);
      expect(sticker.score, 40);
      expect(sticker.recentUses, 3);
      expect(read.emojiFrecency.scoreFor('grinning')!.score, 7);
      expect(read.emojiFrecency.scoreFor('missing'), isNull);
    });

    test('a half-written frecency entry is skipped', () {
      final root = ProtoMessage()
        ..setMessage(
          FrecencyUserSettingsField.emojiFrecency,
          ProtoMessage()
            ..addMessage(1, ProtoMessage()..setString(ProtoMapEntryField.key, 'a'))
            ..addMessage(
              1,
              ProtoMessage()..setMessage(ProtoMapEntryField.value, ProtoMessage()),
            ),
        );

      expect(
        DiscordFrecencyProtoCodec.decodeMessage(root).emojiFrecency.isEmpty,
        isTrue,
      );
    });

    test('a blob with no tables ranks nothing and keeps the order given', () {
      const frecency = ExpressionFrecency.empty;

      expect(frecency.isEmpty, isTrue);
      expect(frecency.rank(['a', 'b', 'c']), ['a', 'b', 'c']);
    });

    test('ranking puts what was used most first', () {
      const frecency = ExpressionFrecency({
        'rare': FrecencyScore(score: 1),
        'often': FrecencyScore(score: 90),
      });

      // Anything the table says nothing about sorts as zero rather than
      // being dropped: an emoji never used is still in the picker.
      expect(frecency.rank(['rare', 'unknown', 'often']), [
        'often',
        'rare',
        'unknown',
      ]);
    });

    test('the tables survive a write untouched', () {
      final root = ProtoMessage()
        ..setMessage(
          FrecencyUserSettingsField.emojiFrecency,
          ProtoMessage()
            ..addMessage(
              1,
              ProtoMessage()
                ..setString(ProtoMapEntryField.key, 'grinning')
                ..setMessage(
                  ProtoMapEntryField.value,
                  ProtoMessage()..setVarint(FrecencyItemField.score, 5),
                ),
            ),
        );

      final written = DiscordFrecencyProtoCodec.apply(
        root,
        const ExpressionFavorites(emojis: ['smile']),
      );

      // Counting a use is the server's job; a client writing its own figures
      // would fight what the other sessions counted.
      expect(
        DiscordFrecencyProtoCodec.decodeMessage(
          written,
        ).emojiFrecency.scoreFor('grinning')?.score,
        5,
      );
    });
  });

  group('what a write puts back', () {
    test('the groups nobody models survive it', () {
      final root = ProtoMessage()
        // application_frecency: a group with no codec here.
        ..setMessage(9, ProtoMessage()..setVarint(1, 42));

      final written = DiscordFrecencyProtoCodec.apply(
        root,
        const ExpressionFavorites(stickerIds: ['5']),
      );

      expect(written.messageAt(9)?.varintAt(1), 42);
      expect(DiscordFrecencyProtoCodec.decodeMessage(written).stickerIds, ['5']);
    });

    test('a sticker id that is not a number is not written', () {
      // Nothing should ever put one here, but a fixed64 cannot carry it and
      // silently writing a zero would favourite a sticker nobody starred.
      final written = DiscordFrecencyProtoCodec.apply(
        ProtoMessage(),
        const ExpressionFavorites(stickerIds: ['nonsense', '6']),
      );

      expect(DiscordFrecencyProtoCodec.decodeMessage(written).stickerIds, ['6']);
    });

    test('a round trip keeps every field', () {
      const favorites = ExpressionFavorites(
        gifs: [
          FavoriteGif(
            url: 'a',
            src: 'b',
            format: FavoriteGifFormat.video,
            width: 4,
            height: 2,
            order: 9,
          ),
        ],
        stickerIds: ['12'],
        emojis: ['smile'],
        hideGifTooltip: true,
      );

      final read = DiscordFrecencyProtoCodec.decodeMessage(
        DiscordFrecencyProtoCodec.apply(ProtoMessage(), favorites),
      );

      expect(read.gifs.single, favorites.gifs.single);
      expect(read.stickerIds, ['12']);
      expect(read.emojis, ['smile']);
      expect(read.hideGifTooltip, isTrue);
    });

    test('the GIF budget is measured, not counted', () {
      final small = ExpressionFavorites(
        gifs: [for (var index = 0; index < 40; index++) _gif('$index')],
      );
      final huge = ExpressionFavorites(
        gifs: [
          for (var index = 0; index < 40; index++)
            FavoriteGif(url: 'u' * 20000, src: 's' * 20000, order: index),
        ],
      );

      expect(DiscordFrecencyProtoCodec.fitsGifBudget(small), isTrue);
      expect(DiscordFrecencyProtoCodec.fitsGifBudget(huge), isFalse);
    });
  });

  group('the domain', () {
    test('the next GIF sorts above everything held', () {
      expect(const ExpressionFavorites().nextGifOrder, 1);
      expect(
        ExpressionFavorites(gifs: [_gif('a', order: 4), _gif('b', order: 2)])
            .nextGifOrder,
        5,
      );
    });

    test('the limits are the client\'s own', () {
      final full = ExpressionFavorites(
        stickerIds: [for (var i = 0; i < expressionFavoritesLimit; i++) '$i'],
        emojis: [for (var i = 0; i < expressionFavoritesLimit; i++) '$i'],
      );

      expect(full.canAddSticker, isFalse);
      expect(full.canAddEmoji, isFalse);
      expect(const ExpressionFavorites().canAddSticker, isTrue);
      expect(const ExpressionFavorites().canAddEmoji, isTrue);
    });

    test('membership is answered per kind', () {
      final favorites = ExpressionFavorites(
        gifs: [_gif('a')],
        stickerIds: const ['1'],
        emojis: const ['smile'],
      );

      expect(favorites.isFavoriteGif('a'), isTrue);
      expect(favorites.isFavoriteGif('b'), isFalse);
      expect(favorites.isFavoriteSticker('1'), isTrue);
      expect(favorites.isFavoriteSticker('2'), isFalse);
      expect(favorites.isFavoriteEmoji('smile'), isTrue);
      expect(favorites.isFavoriteEmoji('frown'), isFalse);
    });

    test('a copy keeps what it was not asked to change', () {
      final favorites = ExpressionFavorites(
        gifs: [_gif('a')],
        stickerIds: const ['1'],
        emojis: const ['smile'],
        hideGifTooltip: true,
      );

      final same = favorites.copyWith();
      expect(same.gifs, favorites.gifs);
      expect(same.stickerIds, ['1']);
      expect(same.emojis, ['smile']);
      expect(same.hideGifTooltip, isTrue);

      final changed = favorites.copyWith(
        gifs: const [],
        stickerIds: const [],
        emojis: const [],
        hideGifTooltip: false,
      );
      expect(changed.isEmpty, isTrue);
      expect(changed.hideGifTooltip, isFalse);
    });

    test('two GIFs are the same one only field for field', () {
      expect(_gif('a'), _gif('a'));
      expect(_gif('a').hashCode, _gif('a').hashCode);
      expect(_gif('a') == _gif('b'), isFalse);
      expect(_gif('a') == const FavoriteGif(url: 'a', src: 'other'), isFalse);
      expect(
        _gif('a') == const FavoriteGif(url: 'a', src: 'src-a', width: 9),
        isFalse,
      );
      expect(_gif('a') == Object(), isFalse);
    });

    test('the codes are the ones the desktop bundle ships', () {
      expect(FavoriteGifFormat.fromCode(1), FavoriteGifFormat.image);
      expect(FavoriteGifFormat.fromCode(2), FavoriteGifFormat.video);
      expect(FavoriteGifFormat.fromCode(0), FavoriteGifFormat.none);
      expect(FavoriteGifFormat.fromCode(null), FavoriteGifFormat.none);
      expect(FavoriteGifFormat.video.code, 2);
    });
  });

  group('the store', () {
    test('an account with no blob loads empty and stays loaded', () async {
      final transport = _FakeTransport();
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);

      expect(store.isLoaded, isFalse);
      expect(await store.load(), ExpressionFavorites.empty);
      expect(store.isLoaded, isTrue);

      // A second call spends no second request.
      await store.load();
      expect(transport.reads, 1);
    });

    test('two loads at once share one request', () async {
      final transport = _FakeTransport();
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);

      await Future.wait([store.load(), store.load()]);

      expect(transport.reads, 1);
    });

    test('an undecodable blob leaves the store empty rather than broken',
        () async {
      final transport = _FakeTransport()..blob = 'not base64 at all !!';
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);

      expect((await store.load()).isEmpty, isTrue);
      expect(store.isLoaded, isTrue);
    });


    test('a write says which version of the blob it was built on', () async {
      final root = ProtoMessage()
        ..setMessage(
          FrecencyUserSettingsField.versions,
          ProtoMessage()..setVarint(3, 11),
        );
      final transport = _FakeTransport()..blob = _base64(root.encode());
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);
      await store.load();

      await store.setEmojiFavorite(idOrName: 'smile', favorite: true);

      // The same guard the preloaded settings use: without it a star made
      // here overwrites whatever another device starred in between.
      expect(transport.writtenVersions, [11]);
    });

    test('starring a GIF writes it and shows it at once', () async {
      final transport = _FakeTransport();
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);
      final seen = <ExpressionFavorites>[];
      store.updates.listen(seen.add);

      expect(
        await store.setGifFavorite(
          gif: const FavoriteGif(url: 'a', src: 'a'),
          favorite: true,
        ),
        isTrue,
      );

      expect(store.current.gifs.single.url, 'a');
      expect(store.current.gifs.single.order, 1);
      expect(_decodeWrite(transport).gifs.single.url, 'a');
      await Future<void>.delayed(Duration.zero);
      expect(seen, isNotEmpty);
    });

    test('a third GIF retires the hint', () async {
      final transport = _FakeTransport();
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);

      for (final url in ['a', 'b', 'c']) {
        await store.setGifFavorite(
          gif: FavoriteGif(url: url, src: url),
          favorite: true,
        );
      }

      expect(store.current.gifs.length, 3);
      expect(store.current.hideGifTooltip, isTrue);
      // Newest first, and each one numbered above the last.
      expect(store.current.gifs.first.url, 'c');
      expect(store.current.gifs.first.order, 3);
    });

    test('a GIF that would not fit is refused rather than written', () async {
      final transport = _FakeTransport()
        ..blob = _base64(
          _blob(
            gifs: {
              for (var index = 0; index < 40; index++)
                'u$index${'x' * 20000}': _gifEntry(order: index),
            },
          ),
        );
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);
      await store.load();

      expect(
        await store.setGifFavorite(
          gif: const FavoriteGif(url: 'one-more', src: 'one-more'),
          favorite: true,
        ),
        isFalse,
      );

      expect(transport.writes, isEmpty);
      expect(store.current.isFavoriteGif('one-more'), isFalse);
    });

    test('unstarring a GIF nobody starred spends no request', () async {
      final transport = _FakeTransport();
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);

      expect(
        await store.setGifFavorite(
          gif: const FavoriteGif(url: 'a', src: 'a'),
          favorite: false,
        ),
        isTrue,
      );

      expect(transport.writes, isEmpty);
    });

    test('starring the same GIF twice keeps one entry', () async {
      final transport = _FakeTransport();
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);

      await store.setGifFavorite(
        gif: const FavoriteGif(url: 'a', src: 'a'),
        favorite: true,
      );
      await store.setGifFavorite(
        gif: const FavoriteGif(url: 'a', src: 'newer'),
        favorite: true,
      );

      expect(store.current.gifs.length, 1);
      expect(store.current.gifs.single.src, 'newer');
    });

    test('a sticker is starred and unstarred', () async {
      final transport = _FakeTransport();
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);

      expect(
        await store.setStickerFavorite(stickerId: '7', favorite: true),
        isTrue,
      );
      expect(store.current.stickerIds, ['7']);
      // Already there: the answer is yes, and no request goes out.
      expect(
        await store.setStickerFavorite(stickerId: '7', favorite: true),
        isTrue,
      );
      expect(transport.writes.length, 1);

      expect(
        await store.setStickerFavorite(stickerId: '7', favorite: false),
        isTrue,
      );
      expect(store.current.stickerIds, isEmpty);
    });

    test('the 251st sticker and emoji are refused', () async {
      final transport = _FakeTransport()
        ..blob = _base64(
          _blob(
            stickerIds: [
              for (var i = 0; i < expressionFavoritesLimit; i++) 100 + i,
            ],
            emojis: [for (var i = 0; i < expressionFavoritesLimit; i++) 'e$i'],
          ),
        );
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);
      await store.load();

      expect(
        await store.setStickerFavorite(stickerId: '9', favorite: true),
        isFalse,
      );
      expect(
        await store.setEmojiFavorite(idOrName: 'new', favorite: true),
        isFalse,
      );
      expect(transport.writes, isEmpty);
    });

    test('an emoji is starred and unstarred', () async {
      final transport = _FakeTransport();
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);

      await store.setEmojiFavorite(idOrName: 'grinning', favorite: true);
      expect(store.current.emojis, ['grinning']);
      expect(
        await store.setEmojiFavorite(idOrName: 'grinning', favorite: true),
        isTrue,
      );

      await store.setEmojiFavorite(idOrName: 'grinning', favorite: false);
      expect(store.current.emojis, isEmpty);
    });

    test('the merged blob the server answers with replaces what was sent',
        () async {
      final transport = _FakeTransport()
        ..response = DiscordSettingsWriteResult(
          settings: _base64(_blob(emojis: ['from-server'])),
        );
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);

      await store.setEmojiFavorite(idOrName: 'mine', favorite: true);

      expect(store.current.emojis, ['from-server']);
    });

    test('a stale write is dropped and the held blob re-read', () async {
      final transport = _FakeTransport()
        ..response = const DiscordSettingsWriteResult(outOfDate: true);
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);
      transport.blob = _base64(_blob(emojis: ['held']));

      expect(
        await store.setEmojiFavorite(idOrName: 'mine', favorite: true),
        isFalse,
      );

      expect(store.current.emojis, ['held']);
    });

    test('a failed write puts the star back', () async {
      final transport = _FakeTransport()
        ..blob = _base64(_blob(emojis: ['held']))
        ..failWrite = true;
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);
      await store.load();

      expect(
        await store.setEmojiFavorite(idOrName: 'mine', favorite: true),
        isFalse,
      );

      expect(store.current.emojis, ['held']);
    });

    test('a failed write whose re-read also fails says so and stops', () async {
      final transport = _FakeTransport()
        ..failWrite = true
        ..failReadAfterFirst = true;
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);
      await store.load();

      expect(
        await store.setEmojiFavorite(idOrName: 'mine', favorite: true),
        isFalse,
      );

      // Nothing better is known, so the optimistic value is what is left.
      expect(store.current.emojis, ['mine']);
    });

    test('a write against an account whose blob went away empties it',
        () async {
      final transport = _FakeTransport()
        ..blob = _base64(_blob(emojis: ['held']))
        ..failWrite = true
        ..clearBlobOnRead = true;
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);
      await store.load();

      await store.setEmojiFavorite(idOrName: 'mine', favorite: true);

      expect(store.current.isEmpty, isTrue);
    });

    test('a star made on another device arrives as a dispatch', () async {
      final transport = _FakeTransport();
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);

      store.acceptGatewayDispatch('USER_SETTINGS_PROTO_UPDATE', {
        'settings': {'type': 2, 'proto': _base64(_blob(emojis: ['elsewhere']))},
      });

      expect(store.current.emojis, ['elsewhere']);
      expect(store.isLoaded, isTrue);
    });

    test('a dispatch for the other settings type is left alone', () {
      final store = DiscordExpressionFavoritesRepository(_FakeTransport());
      addTearDown(store.close);

      for (final dispatch in [
        ('READY', <String, Object?>{'user_settings_proto': 'ignored'}),
        (
          'USER_SETTINGS_PROTO_UPDATE',
          <String, Object?>{
            'settings': {'type': 1, 'proto': 'ignored'},
          },
        ),
        ('USER_SETTINGS_PROTO_UPDATE', <String, Object?>{'settings': 'nonsense'}),
        (
          'USER_SETTINGS_PROTO_UPDATE',
          <String, Object?>{
            'settings': {'type': 2},
          },
        ),
      ]) {
        store.acceptGatewayDispatch(dispatch.$1, dispatch.$2);
      }

      expect(store.isLoaded, isFalse);
    });

    test('a partial update before the blob is ignored, and after it merges',
        () async {
      final transport = _FakeTransport()
        ..blob = _base64(_blob(emojis: ['held'], stickerIds: [5]));
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);

      store.acceptGatewayDispatch('USER_SETTINGS_PROTO_UPDATE', {
        'partial': true,
        'settings': {'type': 2, 'proto': _base64(_blob(emojis: ['partial']))},
      });
      expect(store.isLoaded, isFalse);

      await store.load();
      store.acceptGatewayDispatch('USER_SETTINGS_PROTO_UPDATE', {
        'partial': true,
        'settings': {'type': 2, 'proto': _base64(_blob(emojis: ['partial']))},
      });

      expect(store.current.emojis, ['partial']);
      // The group the partial did not name is still held.
      expect(store.current.stickerIds, ['5']);
    });

    test('an undecodable dispatch changes nothing', () async {
      final transport = _FakeTransport();
      final store = DiscordExpressionFavoritesRepository(transport);
      addTearDown(store.close);
      await store.load();

      store.acceptGatewayDispatch('USER_SETTINGS_PROTO_UPDATE', {
        'settings': {'type': 2, 'proto': 'not base64 at all !!'},
      });

      expect(store.current.isEmpty, isTrue);
    });

    test('a star after the store closed is not published to nobody', () async {
      final transport = _FakeTransport();
      final store = DiscordExpressionFavoritesRepository(transport);
      await store.load();
      await store.close();

      // Closing must not make a late dispatch throw on a dead controller.
      store.acceptGatewayDispatch('USER_SETTINGS_PROTO_UPDATE', {
        'settings': {'type': 2, 'proto': _base64(_blob(emojis: ['late']))},
      });

      expect(store.current.emojis, ['late']);
    });
  });
}

FavoriteGif _gif(String url, {int order = 0}) =>
    FavoriteGif(url: url, src: 'src-$url', order: order);

ProtoMessage _gifEntry({
  String? src,
  int format = 0,
  int width = 0,
  int height = 0,
  int order = 0,
}) {
  final value = ProtoMessage()
    ..setVarint(FavoriteGifField.format, format)
    ..setVarint(FavoriteGifField.width, width)
    ..setVarint(FavoriteGifField.height, height)
    ..setVarint(FavoriteGifField.order, order);
  if (src != null) value.setString(FavoriteGifField.src, src);
  return value;
}

Uint8List _blob({
  Map<String, ProtoMessage> gifs = const {},
  List<int> stickerIds = const [],
  List<String> emojis = const [],
  bool hideTooltip = false,
}) {
  final root = ProtoMessage();
  if (gifs.isNotEmpty || hideTooltip) {
    final group = ProtoMessage();
    gifs.forEach((url, value) {
      group.addMessage(
        FavoriteGifsField.gifs,
        ProtoMessage()
          ..setString(ProtoMapEntryField.key, url)
          ..setMessage(ProtoMapEntryField.value, value),
      );
    });
    if (hideTooltip) group.setBool(FavoriteGifsField.hideTooltip, true);
    root.setMessage(FrecencyUserSettingsField.favoriteGifs, group);
  }
  if (stickerIds.isNotEmpty) {
    root.setMessage(
      FrecencyUserSettingsField.favoriteStickers,
      ProtoMessage()
        ..setFixed64List(FavoriteStickersField.stickerIds, stickerIds),
    );
  }
  if (emojis.isNotEmpty) {
    root.setMessage(
      FrecencyUserSettingsField.favoriteEmojis,
      ProtoMessage()..setStrings(FavoriteEmojisField.emojis, emojis),
    );
  }
  return root.encode();
}

String _base64(Uint8List bytes) => base64.encode(bytes);

ExpressionFavorites _decodeWrite(_FakeTransport transport) =>
    DiscordFrecencyProtoCodec.decode(
      Uint8List.fromList(base64.decode(transport.writes.last)),
    );

final class _FakeTransport implements DiscordUserSettingsTransport {
  final List<String> writes = [];
  final List<int?> writtenVersions = [];
  int reads = 0;
  String? blob;
  bool failWrite = false;
  bool failReadAfterFirst = false;
  bool clearBlobOnRead = false;
  DiscordSettingsWriteResult response = const DiscordSettingsWriteResult();

  @override
  Future<String?> readSettingsProto(int type) async {
    expect(type, 2);
    reads++;
    if (failReadAfterFirst && reads > 1) throw StateError('read failed');
    if (clearBlobOnRead && reads > 1) return null;
    return blob;
  }

  @override
  Future<DiscordSettingsWriteResult> writeSettingsProto({
    required int type,
    required String settings,
    int? requiredDataVersion,
  }) async {
    expect(type, 2);
    if (failWrite) throw StateError('write failed');
    writes.add(settings);
    writtenVersions.add(requiredDataVersion);
    return response;
  }
}
