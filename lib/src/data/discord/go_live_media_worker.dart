import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../app_log.dart';
import '../../domain/go_live_media.dart';
import '../../domain/go_live_stream.dart';
import '../../domain/video_encoder.dart';
import '../../domain/voice_connection.dart';
import 'discord_voice_socket_factory.dart';
import 'go_live_sender.dart';

// What crosses between the main isolate and the media worker. Plain values
// only: a message with a closure or a native handle in it cannot be sent,
// and the send throws.

/// Main to worker: open a Sender, which dials at once.
final class MediaOpen {
  const MediaOpen({
    required this.id,
    required this.credentials,
    required this.streamKey,
    required this.settings,
    required this.maxDaveProtocolVersion,
  });

  final int id;
  final VoiceServerCredentials credentials;
  final GoLiveStreamKey streamKey;
  final VideoEncoderSettings settings;
  final int maxDaveProtocolVersion;
}

final class MediaReshape {
  const MediaReshape({required this.id, required this.settings});

  final int id;
  final VideoEncoderSettings settings;
}

final class MediaAudio {
  const MediaAudio({required this.id, required this.opus});

  final int id;
  final Uint8List opus;
}

final class MediaClose {
  const MediaClose(this.id);

  final int id;
}

final class MediaShutdown {
  const MediaShutdown();
}

/// Worker to main: the worker is up, with its inbox and where the native
/// encoder delivers frames.
final class MediaHello {
  const MediaHello({required this.port, required this.frameSink});

  final SendPort port;
  final int? frameSink;
}

final class MediaStatus {
  const MediaStatus({required this.id, required this.status});

  final int id;
  final GoLiveSenderStatus status;
}

final class MediaCommand {
  const MediaCommand({required this.id, required this.command});

  final int id;
  final GoLiveEncoderCommand command;
}

final class MediaPaceLine {
  const MediaPaceLine({required this.id, required this.line});

  final int id;
  final String line;
}

final class MediaFrame {
  const MediaFrame({
    required this.bytes,
    required this.timestampUs,
    required this.isKeyframe,
  });

  final TransferableTypedData bytes;
  final int timestampUs;
  final bool isKeyframe;
}

final class MediaLog {
  const MediaLog({
    required this.level,
    required this.scope,
    required this.message,
    required this.error,
  });

  final AppLogLevel level;
  final String scope;
  final String message;
  final String? error;
}

final class MediaClosed {
  const MediaClosed(this.id);

  final int id;
}

/// The Senders the worker holds, by the id the main isolate gave them.
///
/// Sockets come from the injected factory: the real gateway factory in the
/// app, built on the worker so the group encryptor is created, keyed and
/// used on one thread; a fake in tests.
final class GoLiveMediaWorker {
  GoLiveMediaWorker({
    required SendPort toMain,
    required Stream<EncodedVideoFrame> frames,
    required DiscordVoiceSocketFactory Function(int maxDaveProtocolVersion)
    socketFactory,
    Duration paceInterval = const Duration(seconds: 5),
  }) : _toMain = toMain,
       _frames = frames,
       _socketFactory = socketFactory,
       _paceInterval = paceInterval;

  static const _scope = 'golive.media';

  final SendPort _toMain;
  final Stream<EncodedVideoFrame> _frames;
  final DiscordVoiceSocketFactory Function(int maxDaveProtocolVersion)
  _socketFactory;
  final Duration _paceInterval;
  final Map<int, _Held> _senders = {};

  /// Handles [inbox] until a [MediaShutdown], then closes every Sender.
  ///
  /// One bad message must not end the loop: a throw here used to terminate
  /// the isolate, and every stream after it hung at "dialling" against a
  /// worker that no longer read its inbox.
  Future<void> run(Stream<Object?> inbox) async {
    await for (final message in inbox) {
      if (message is MediaShutdown) break;
      try {
        handle(message);
      } on Object catch (error, stackTrace) {
        _toMain.send(
          MediaLog(
            level: AppLogLevel.error,
            scope: _scope,
            message: 'message failed',
            error: '$error\n$stackTrace',
          ),
        );
      }
    }
    await closeAll();
  }

  void handle(Object? message) {
    switch (message) {
      case MediaOpen():
        _open(message);
      case MediaReshape(:final id, :final settings):
        _senders[id]?.sender.reshape(settings);
      case MediaAudio(:final id, :final opus):
        _senders[id]?.sender.sendOpusFrame(opus);
      case MediaClose(:final id):
        unawaited(_close(id));
    }
  }

  void _open(MediaOpen open) {
    final GoLiveWireSender sender;
    try {
      sender = GoLiveWireSender(
        client: _socketFactory(open.maxDaveProtocolVersion).streamSocket(
          credentials: open.credentials,
          streamKey: open.streamKey,
        ),
        frames: _frames,
        settings: open.settings,
        paceInterval: _paceInterval,
      );
    } on Object catch (error) {
      AppLog.error(_scope, 'open failed', error: error);
      _toMain.send(MediaStatus(id: open.id, status: GoLiveSenderStatus.failed));
      return;
    }
    _senders[open.id] = _Held(
      sender: sender,
      subscriptions: [
        sender.statuses.listen(
          (status) => _toMain.send(MediaStatus(id: open.id, status: status)),
        ),
        sender.encoderCommands.listen(
          (command) =>
              _toMain.send(MediaCommand(id: open.id, command: command)),
        ),
        sender.paceLines.listen(
          (line) => _toMain.send(MediaPaceLine(id: open.id, line: line)),
        ),
      ],
    );
  }

  Future<void> _close(int id) async {
    await _senders.remove(id)?.close();
    _toMain.send(MediaClosed(id));
  }

  Future<void> closeAll() async {
    for (final id in _senders.keys.toList(growable: false)) {
      await _close(id);
    }
  }
}

final class _Held {
  _Held({required this.sender, required this.subscriptions});

  final GoLiveWireSender sender;
  final List<StreamSubscription<Object?>> subscriptions;

  Future<void> close() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await sender.close();
  }
}
