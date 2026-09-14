import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/video_decoder.dart';

/// The picture this account sees of its own stream.
///
/// The sender's tile uses the same stream viewer as every other tile, drawing
/// the encoder's own pictures decoded locally (ADR-0001). A decoder that would
/// not open is shown as such rather than as an empty tile.
final class VoiceSelfPreview {
  const VoiceSelfPreview({required this.frames, this.error});

  final Stream<DecodedVideoFrame> frames;
  final Object? error;
}

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
    this.selfPreview,
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

  /// The stream this account receives back while sharing, or null before the
  /// share has a key. It replaces the sender's avatar tile, not the room stage.
  final VoiceSelfPreview? selfPreview;
}
