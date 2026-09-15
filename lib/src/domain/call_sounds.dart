/// The sounds a call makes, as bundled assets.
///
/// Ring, accept, and hang-up are played through the same media playback
/// layer the soundboard uses, from assets bundled with the client: no new
/// audio path, and a build whose assets are missing simply stays silent
/// rather than failing a call over a sound.
final class CallSounds {
  const CallSounds({
    this.ring = 'asset://assets/sounds/call_ring.wav',
    this.accept = 'asset://assets/sounds/call_accept.wav',
    this.hangUp = 'asset://assets/sounds/call_hang_up.wav',
  });

  /// Played while a call rings for this account.
  final String ring;

  /// Played when this account answers.
  final String accept;

  /// Played when either side hangs up.
  final String hangUp;
}
