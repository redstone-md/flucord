abstract final class DiscordMentionMatcher {
  static bool containsUser(Map<String, Object?> message, String? userId) {
    if (userId == null) return false;
    final mentions = message['mentions'];
    return mentions is List &&
        mentions.whereType<Map>().any((user) => user['id'] == userId);
  }

  static bool containsRole(Map<String, Object?> message, Set<String> roleIds) {
    final mentions = message['mention_roles'];
    return mentions is List && mentions.any(roleIds.contains);
  }
}
