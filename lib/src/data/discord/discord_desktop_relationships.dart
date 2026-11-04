import 'dart:io';

import '../../app_log.dart';
import '../../domain/desktop_relationship_repository.dart';
import '../../domain/discord_relationship.dart';
import '../../domain/discord_remote_auth.dart';
import '../../domain/friend_suggestion.dart';
import '../../domain/relationship_request.dart';
import 'discord_captcha.dart';
import 'discord_desktop_api_client.dart';
import 'discord_relationship_service.dart';
import 'discord_rest_client.dart';

/// The read-only face the surfaces see of the desktop session's friend graph.
///
/// The service itself also folds dispatches in, which is not something a
/// surface should be able to do by holding the same object.
final class DiscordDesktopRelationships
    implements DesktopRelationshipRepository {
  const DiscordDesktopRelationships(this._service, this._api);

  final DiscordRelationshipService _service;
  final DiscordDesktopApiClient _api;

  /// Discord's own code for a block.
  static const _blocked = 2;

  @override
  List<DiscordRelationship> get relationships => _service.relationships;

  @override
  Stream<List<DiscordRelationship>> get relationshipUpdates => _service.updates;

  @override
  List<FriendSuggestion> get friendSuggestions => _service.suggestions;

  @override
  Future<void> loadFriendSuggestions() async {
    final List<Map<String, Object?>> payloads;
    try {
      payloads = await _api.getFriendSuggestions();
    } on Object catch (error) {
      _logFailure('friend suggestions', error);
      rethrow;
    }
    _service.replaceSuggestions([
      for (final payload in payloads)
        ?DiscordRelationshipService.readSuggestion(payload),
    ]);
  }

  /// Sends one relationship write.
  ///
  /// Nothing is patched locally on success: Discord echoes every change back
  /// as RELATIONSHIP_ADD, UPDATE or REMOVE, and a list edited here as well
  /// would disagree with the one the next dispatch installs. A dismissed
  /// suggestion is the exception, since Discord sends nothing back for it.
  @override
  Future<RelationshipResult> send(
    RelationshipRequest request, {
    DiscordCaptchaAnswer? captcha,
  }) async {
    final headers = captcha == null
        ? const <String, String>{}
        : DiscordCaptcha.headersOf(captcha);
    try {
      await switch (request) {
        BefriendUser(:final userId) => _api.putRelationship(
          userId,
          headers: headers,
        ),
        BefriendUsername(:final username) => _api.postRelationshipByUsername(
          username,
          headers: headers,
        ),
        RemoveRelationship(:final userId) => _api.deleteRelationship(
          userId,
          headers: headers,
        ),
        BlockUser(:final userId) => _api.putRelationship(
          userId,
          type: _blocked,
          headers: headers,
        ),
        DismissSuggestion(:final userId) => _api.deleteFriendSuggestion(
          userId,
          headers: headers,
        ),
      };
    } on DiscordApiException catch (error) {
      return _refusalOf(request, error);
    } on Object catch (error) {
      _logFailure(_nameOf(request), error);
      rethrow;
    }
    if (request case DismissSuggestion(:final userId)) {
      _service.forgetSuggestion(userId);
    }
    return const RelationshipDone();
  }

  /// What a refused [request] means, or a rethrow when it is no refusal: a
  /// server error, or a session Discord no longer accepts.
  RelationshipResult _refusalOf(
    RelationshipRequest request,
    DiscordApiException error,
  ) {
    final status = error.statusCode;
    final name = _nameOf(request);
    final challenge = _api.captchaChallengeOf(error);
    if (challenge != null) {
      AppLog.warning('friends', '$name needs a captcha, status $status');
      return RelationshipCaptchaRequired(challenge);
    }
    if (status < 400 || status >= 500 || status == HttpStatus.unauthorized) {
      _logFailure(name, error);
      throw error;
    }
    final code = _codeOf(error);
    AppLog.warning(
      'friends',
      '$name refused, status $status, code ${code ?? 'none'}',
    );
    return RelationshipRefused(
      status == HttpStatus.tooManyRequests
          ? RelationshipRefusal.tooManyRequests
          : _refusals[code] ?? RelationshipRefusal.other,
      code: code,
    );
  }

  static int? _codeOf(DiscordApiException error) =>
      switch (error.responsePayload?['code']) {
        final int value => value,
        _ => null,
      };

  /// Discord's error codes for the refusals this build can explain.
  static const _refusals = {
    10013: RelationshipRefusal.unknownUser,
    80004: RelationshipRefusal.unknownUser,
    80007: RelationshipRefusal.alreadyFriends,
    80000: RelationshipRefusal.notAccepting,
    80001: RelationshipRefusal.notAccepting,
    80002: RelationshipRefusal.bot,
    80003: RelationshipRefusal.self,
    30002: RelationshipRefusal.friendLimit,
    40002: RelationshipRefusal.unverifiedAccount,
    340007: RelationshipRefusal.limited,
    80005: RelationshipRefusal.noIncomingRequest,
  };

  /// What [request] is, for the log. Never the user or the name it is for.
  static String _nameOf(RelationshipRequest request) => switch (request) {
    BefriendUser() => 'friend request',
    BefriendUsername() => 'friend request by username',
    RemoveRelationship() => 'relationship removal',
    BlockUser() => 'block',
    DismissSuggestion() => 'suggestion dismissal',
  };

  /// Logs a failure by its kind and status only: an error's own text can
  /// carry a name or an address.
  static void _logFailure(String name, Object error) =>
      AppLog.warning('friends', switch (error) {
        final DiscordApiException failure =>
          '$name failed, status ${failure.statusCode}, '
              'code ${_codeOf(failure) ?? 'none'}',
        _ => '$name failed: ${error.runtimeType}',
      });
}
