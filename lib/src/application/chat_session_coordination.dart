import 'dart:async';

import 'account_entitlements_controller.dart';
import 'chat_controller.dart';
import 'direct_call_controller.dart';
import 'game_detection_controller.dart';
import 'go_live_controller.dart';
import 'self_presence_controller.dart';
import 'soundboard_playback_controller.dart';
import 'user_profile_controller.dart';
import 'user_settings_controller.dart';
import 'voice_controller.dart';
import '../data/discord/discord_stream_rtc_service.dart';

/// Keeps everything that reads the chat session in step with it.
///
/// The session is swapped underneath the app: an account signs in, a
/// transport replaces another, and every controller that resolves its plane
/// through a provider has to re-read it. The voice plane goes further and
/// rebinds, because a transport that came and went leaves a call wired to a
/// socket that is already closed. These rules used to sit in the app widget,
/// where no test could reach them without pumping the whole client.
final class ChatSessionCoordination {
  ChatSessionCoordination({
    required ChatController chat,
    required VoiceController voice,
    required DirectCallController directCall,
    required DiscordStreamRtcService streamRtc,
    required UserSettingsController userSettings,
    required UserProfileController userProfile,
    required SoundboardPlaybackController soundboardPlayback,
    required GoLiveController goLive,
    required SelfPresenceController selfPresence,
    required GameDetectionController gameDetection,
    AccountEntitlementsController? accountEntitlements,
  }) : _chat = chat,
       _voice = voice,
       _directCall = directCall,
       _streamRtc = streamRtc,
       _userSettings = userSettings,
       _userProfile = userProfile,
       _soundboardPlayback = soundboardPlayback,
       _goLive = goLive,
       _selfPresence = selfPresence,
       _gameDetection = gameDetection,
       _accountEntitlements = accountEntitlements {
    _chat.addListener(_sessionChanged);
  }

  final ChatController _chat;
  final VoiceController _voice;
  final DirectCallController _directCall;
  final DiscordStreamRtcService _streamRtc;
  final UserSettingsController _userSettings;
  final UserProfileController _userProfile;
  final SoundboardPlaybackController _soundboardPlayback;
  final GoLiveController _goLive;
  final SelfPresenceController _selfPresence;
  final GameDetectionController _gameDetection;

  /// What the account holds, loaded once per session so the surfaces that
  /// answer from it, the composer's limits, do not have to ask first.
  final AccountEntitlementsController? _accountEntitlements;

  void dispose() {
    _chat.removeListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (_chat.state == ChatLoadState.ready) {
      unawaited(_voice.refreshSignalingService());
      _directCall.reconcileService();
      _streamRtc.reconcile();
    }
    _userSettings.reconcile();
    _userProfile.reconcile();
    _accountEntitlements?.load();
    _soundboardPlayback.reconcile();
    _goLive.reconcile();
    _selfPresence.reconcile();
    _gameDetection.reconcile();
  }
}
