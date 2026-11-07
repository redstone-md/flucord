import 'dart:io';

import 'package:flucord/src/data/discord/discord_sound_assets.dart';
import 'package:flucord/src/data/discord_sound_library.dart';
import 'package:flucord/src/domain/client_sounds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('sounds'));
  tearDown(() => directory.deleteSync(recursive: true));

  DiscordSoundLibrary libraryWith(_FakeFetcher fetcher) =>
      DiscordSoundLibrary(fetcher: fetcher, directory: () async => directory);

  test('every client sound has a pinned Discord file', () {
    for (final sound in ClientSound.values) {
      expect(discordSoundFiles, contains(sound.discordName));
    }
  });

  test('a miss fetches from Discord in the background and caches', () async {
    final fetcher = _FakeFetcher();
    final library = libraryWith(fetcher);

    expect(await library.localUrl(ClientSound.message), isNull);
    // Waits for the fetch the miss started, and fetches the rest.
    await library.fetchAll();

    expect(
      fetcher.asked,
      contains(Uri.parse('https://discord.com/assets/3ed22d14f3c30bc4.mp3')),
    );
    final url = await library.localUrl(ClientSound.message);
    expect(url, startsWith('file://'));
    expect(File.fromUri(Uri.parse(url!)).readAsBytesSync(), [1, 2, 3]);
  });

  test('a cached sound is found without the network', () async {
    await libraryWith(_FakeFetcher()).fetchAll();

    final offline = _FakeFetcher(fail: true);
    final url = await libraryWith(offline).localUrl(ClientSound.mute);

    expect(url, isNotNull);
    expect(offline.asked, isEmpty);
  });

  test('a sound that cannot be fetched stays missing, quietly', () async {
    final fetcher = _FakeFetcher(fail: true);
    final library = libraryWith(fetcher);

    await library.fetchAll();

    expect(fetcher.asked, hasLength(ClientSound.values.length));
    expect(await library.localUrl(ClientSound.mute), isNull);
    expect(directory.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('two asks for one sound fetch it once', () async {
    final fetcher = _FakeFetcher();
    final library = libraryWith(fetcher);

    await Future.wait([
      library.localUrl(ClientSound.deafen),
      library.localUrl(ClientSound.deafen),
    ]);
    await library.fetchAll();

    expect(fetcher.asked, hasLength(ClientSound.values.length));
  });
}

final class _FakeFetcher implements SoundFetcher {
  _FakeFetcher({this.fail = false});

  final bool fail;
  final List<Uri> asked = [];

  @override
  Future<List<int>> fetch(Uri uri) async {
    asked.add(uri);
    if (fail) throw const SocketException('offline');
    return const [1, 2, 3];
  }
}
