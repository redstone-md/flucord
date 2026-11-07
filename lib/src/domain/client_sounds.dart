/// The sounds the client itself makes, named as Discord's sound module names
/// them.
///
/// Discord's own files are fetched at run time and never shipped (see
/// NOTICE). A sound with a [fallbackAsset] plays that bundled sound until
/// Discord's file is on this machine; the others stay silent until then.
enum ClientSound {
  message('message1'),
  mute('mute'),
  unmute('unmute'),
  deafen('deafen'),
  undeafen('undeafen'),
  userJoin('user_join', fallbackAsset: 'asset://assets/sounds/call_accept.wav'),
  userLeave('user_leave'),
  userMoved('user_moved'),
  disconnect(
    'disconnect',
    fallbackAsset: 'asset://assets/sounds/call_hang_up.wav',
  ),
  callRinging(
    'call_ringing',
    fallbackAsset: 'asset://assets/sounds/call_ring.wav',
  ),
  callCalling(
    'call_calling',
    fallbackAsset: 'asset://assets/sounds/call_ring.wav',
  ),
  streamStarted('stream_started'),
  streamEnded('stream_ended');

  const ClientSound(this.discordName, {this.fallbackAsset});

  /// The key in Discord's sound module, as in `./message1.mp3`.
  final String discordName;

  /// A bundled sound played while Discord's file is missing.
  final String? fallbackAsset;
}

/// Plays client sounds. A call never fails and never waits for the sound.
abstract interface class ClientSoundPlayer {
  /// Plays [sound] once.
  void play(ClientSound sound);

  /// Plays [sound] over and over until [stopLoop], replacing any other loop.
  void loop(ClientSound sound);

  void stopLoop();
}

/// Where Discord's sound files are kept on this machine.
abstract interface class ClientSoundLibrary {
  /// A playable address for [sound] on this machine, or null when it is not
  /// here yet. A miss starts fetching it in the background.
  Future<String?> localUrl(ClientSound sound);

  /// Fetches every sound that is not here yet. Never throws.
  Future<void> fetchAll();
}

/// The switch that turns client sounds off, kept on this machine.
abstract interface class ClientSoundSettingsRepository {
  Future<bool> loadEnabled();

  Future<void> saveEnabled({required bool enabled});
}
