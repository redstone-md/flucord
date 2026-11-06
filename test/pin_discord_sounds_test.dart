import 'dart:io';

import 'package:flucord/src/data/discord/discord_sound_assets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/pin_discord_sounds.dart';

// Shaped like the web client's chunks: a context map from file name to
// module id, and each module exporting its hashed file.
const _entry =
    'let a={"./message1.mp3":"31742","./mute.mp3":"645951",'
    '"./other.mp3":"5"};';
const _chunk =
    ',31742(e,t,n){"use strict";e.exports=n.p+"3ed22d14f3c30bc4.mp3"}'
    ',645951(e,t,n){"use strict";e.exports=n.p+"2d3b4ba32c34c862.mp3"}';

void main() {
  test('finds each sound across the chunks', () {
    expect(pinSounds([_entry, _chunk], ['message1', 'mute']), {
      'message1': '3ed22d14f3c30bc4.mp3',
      'mute': '2d3b4ba32c34c862.mp3',
    });
  });

  test('a sound the bundles no longer name is an error', () {
    expect(
      () => pinSounds([_entry, _chunk], ['message1', 'user_join']),
      throwsA(isA<StateError>()),
    );
  });

  test('the pinned list is what the tool writes', () {
    expect(
      renderSoundAssets(discordSoundFiles),
      File(soundAssetsPath).readAsStringSync(),
    );
  });
}
