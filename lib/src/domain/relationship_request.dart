import 'discord_remote_auth.dart';

/// One change to the friend graph that the account asks Discord for.
///
/// A request is data, so a request Discord held back for a captcha can be
/// sent again as it was, with the solved key.
sealed class RelationshipRequest {
  const RelationshipRequest();
}

/// A friend request to [userId], or the acceptance of theirs. Discord does
/// not tell the two apart.
final class BefriendUser extends RelationshipRequest {
  const BefriendUser(this.userId);

  final String userId;
}

/// A friend request to whoever has [username].
final class BefriendUsername extends RelationshipRequest {
  const BefriendUsername(this.username);

  final String username;
}

/// Removes a friend, declines or cancels a request, or unblocks.
final class RemoveRelationship extends RelationshipRequest {
  const RemoveRelationship(this.userId);

  final String userId;
}

final class BlockUser extends RelationshipRequest {
  const BlockUser(this.userId);

  final String userId;
}

final class DismissSuggestion extends RelationshipRequest {
  const DismissSuggestion(this.userId);

  final String userId;
}

/// What Discord answered to a [RelationshipRequest].
sealed class RelationshipResult {
  const RelationshipResult();
}

final class RelationshipDone extends RelationshipResult {
  const RelationshipDone();
}

/// Discord said no. [code] is Discord's own error code, when it sent one.
final class RelationshipRefused extends RelationshipResult {
  const RelationshipRefused(this.reason, {this.code});

  final RelationshipRefusal reason;
  final int? code;
}

/// Discord wants a captcha solved before it takes the request.
final class RelationshipCaptchaRequired extends RelationshipResult {
  const RelationshipCaptchaRequired(this.challenge);

  final DiscordRemoteAuthCaptchaChallenge challenge;
}

/// Why Discord refused a relationship request.
enum RelationshipRefusal {
  unknownUser,
  alreadyFriends,

  /// They do not take friend requests, or they blocked this account. Discord
  /// asks clients not to reveal a block, so both read the same.
  notAccepting,
  bot,
  self,
  friendLimit,
  unverifiedAccount,
  limited,
  noIncomingRequest,
  tooManyRequests,

  /// A refusal this build has no reason for.
  other,
}
