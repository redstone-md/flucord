import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'chat_controller.dart';
import 'go_live_controller.dart';
import 'voice_controller.dart';
import '../domain/chat_models.dart';

/// Joins a channel and starts a share on its own, when asked to by the
/// environment.
///
/// Screen sharing is the one path that cannot be reached from a test: it
/// needs a live session, a real voice channel, and Discord's answer to a
/// stream it actually created. Reaching it meant asking somebody to press a
/// button and describe what happened, which is how three wrong fixes
/// happened in a row. Debug builds only, off unless the variables are set:
///
///   `FLUCORD_DEV_CHANNEL`: the voice channel to join, by name
///   `FLUCORD_DEV_GOLIVE=1`: and start sharing once it is up
final class DeveloperCheck {
  DeveloperCheck({
    required ChatController chat,
    required VoiceController voice,
    required GoLiveController goLive,
  }) : _chat = chat,
       _voice = voice,
       _goLive = goLive {
    _chat.addListener(_sessionChanged);
  }

  final ChatController _chat;
  final VoiceController _voice;
  final GoLiveController _goLive;

  bool _ran = false;

  void dispose() {
    _chat.removeListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (_chat.state == ChatLoadState.ready) unawaited(run());
  }

  Future<void> run() async {
    if (!kDebugMode || _ran) return;
    final wanted = Platform.environment['FLUCORD_DEV_CHANNEL'];
    if (wanted == null || wanted.isEmpty) return;
    final workspace = _chat.workspace;
    final channel = workspace?.channels
        .where(
          (candidate) =>
              candidate.kind == ChannelKind.voice &&
              candidate.name.toLowerCase().contains(wanted.toLowerCase()),
        )
        .firstOrNull;
    if (channel == null) return;
    _ran = true;
    developer.log('flucord.dev joining ${channel.name}', name: 'flucord.dev');
    stdout.writeln('flucord.dev joining ${channel.name}');
    await _voice.connect(
      guildId: channel.spaceId,
      channelId: channel.id,
    );
    if (Platform.environment['FLUCORD_DEV_GOLIVE'] != '1') return;
    // After the transport has had a moment: a stream created before the call
    // is up is one Discord answers with an endpoint nobody can identify to.
    await Future<void>.delayed(const Duration(seconds: 6));
    stdout.writeln('flucord.dev starting a share');
    await _goLive.start(
      channelId: channel.id,
      guildId: channel.spaceId,
    );
  }
}
