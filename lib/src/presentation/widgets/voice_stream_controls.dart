import 'package:flutter/widgets.dart';

/// What the tiles need to know about the streams this client has open, and the
/// controls they offer for them.
///
/// One value rather than four arguments because the mark answers a question
/// per tile now: which one participant's stream is open cannot be said for the
/// whole room by naming one user.
///
/// It lives apart from the grid and the room that draw it because the pane is
/// what builds it, and neither of them owns the stream plane.
final class VoiceStreamControls {
  const VoiceStreamControls({
    required this.isOpen,
    this.onWatch,
    this.onStopShare,
  });

  /// Whether [userId]'s stream is open here: asked for, or arriving. Asked-for
  /// counts: the ask and the pictures are a second apart, and the ask is the
  /// only half the grid is on screen for.
  final bool Function(String userId) isOpen;

  /// Opens somebody's stream, or closes the one already open. Null on a build
  /// that cannot watch, which is one with no decoder: a call is a room like
  /// any other and gets the same control.
  final void Function(String userId)? onWatch;

  /// Ends this account's own stream, or null while this account is not
  /// sharing. The sender's own tile reads that: the roster reports a stream
  /// only once Discord echoes one back.
  final VoidCallback? onStopShare;
}
