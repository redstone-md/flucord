enum DiscordRelationshipKind {
  friend,
  incomingRequest,
  outgoingRequest,
  blocked,
  implicit,
  unknown,
}

enum DiscordPresenceStatus { online, idle, doNotDisturb, offline, unknown }

enum DiscordRelationshipAction {
  acceptRequest,
  rejectRequest,
  cancelRequest,
  removeFriend,
  blockUser,
}

final class DiscordRelationshipUser {
  factory DiscordRelationshipUser({
    required String id,
    required String displayName,
    String? username,
    String? avatarUrl,
    DiscordPresenceStatus status = DiscordPresenceStatus.unknown,
    bool isProvisional = false,
  }) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
    final normalizedUsername = _optionalText(username);
    final normalizedDisplayName = displayName.trim();
    return DiscordRelationshipUser._(
      id: normalizedId,
      displayName: normalizedDisplayName.isEmpty
          ? normalizedUsername ?? normalizedId
          : normalizedDisplayName,
      username: normalizedUsername,
      avatarUrl: _remoteUrl(avatarUrl),
      status: status,
      isProvisional: isProvisional,
    );
  }

  const DiscordRelationshipUser._({
    required this.id,
    required this.displayName,
    required this.username,
    required this.avatarUrl,
    required this.status,
    required this.isProvisional,
  });

  final String id;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final DiscordPresenceStatus status;
  final bool isProvisional;

  static String? _optionalText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String? _remoteUrl(String? value) {
    final normalized = _optionalText(value);
    final uri = normalized == null ? null : Uri.tryParse(normalized);
    return uri != null &&
            uri.hasAuthority &&
            (uri.scheme == 'https' || uri.scheme == 'http')
        ? uri.toString()
        : null;
  }
}

final class DiscordRelationship {
  const DiscordRelationship({
    required this.user,
    required this.kind,
    this.isSpamRequest = false,
  });

  final DiscordRelationshipUser user;
  final DiscordRelationshipKind kind;
  final bool isSpamRequest;

  bool get isPending =>
      kind == DiscordRelationshipKind.incomingRequest ||
      kind == DiscordRelationshipKind.outgoingRequest;

  bool supports(DiscordRelationshipAction action) => switch ((kind, action)) {
    (
      DiscordRelationshipKind.incomingRequest,
      DiscordRelationshipAction.acceptRequest ||
          DiscordRelationshipAction.rejectRequest ||
          DiscordRelationshipAction.blockUser,
    ) =>
      true,
    (
      DiscordRelationshipKind.outgoingRequest,
      DiscordRelationshipAction.cancelRequest ||
          DiscordRelationshipAction.blockUser,
    ) =>
      true,
    (
      DiscordRelationshipKind.friend,
      DiscordRelationshipAction.removeFriend ||
          DiscordRelationshipAction.blockUser,
    ) =>
      true,
    _ => false,
  };

  DiscordRelationship withKind(DiscordRelationshipKind nextKind) =>
      DiscordRelationship(
        user: user,
        kind: nextKind,
        isSpamRequest: isSpamRequest,
      );
}

final class DiscordSocialSdkException implements Exception {
  const DiscordSocialSdkException(this.code);

  final String code;

  @override
  String toString() => 'DiscordSocialSdkException($code)';
}
