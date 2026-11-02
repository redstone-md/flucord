import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';

/// The cached workspace an offline launch may show to [accountId], or null.
///
/// One cache file serves whoever signs in on this machine, so what it holds may
/// belong to another account. Only a cache that names [accountId] is returned.
/// A null [accountId] means the credential does not say whose it is, and then
/// nothing proves the cache is theirs.
Future<ChatWorkspace?> readOfflineWorkspace(
  ChatCache cache,
  String? accountId,
) async {
  if (accountId == null) return null;
  final cached = await cache.readWorkspace();
  return cached?.currentMemberId == accountId ? cached : null;
}

/// Empties the cache, and the pictures of its chats, when another account
/// filled it.
///
/// Call this once Discord has said who [accountId] is, and before the live
/// workspace is written. That write replaces the navigation only: without this,
/// the first account's messages and members would stay, and would show in any
/// channel the two accounts share. The pictures are on disk apart from the
/// cache, so [clearChatImages] removes them too.
Future<void> clearCacheOfOtherAccount(
  ChatCache cache,
  String accountId, {
  required Future<void> Function()? clearChatImages,
}) async {
  final held = await cache.readWorkspaceShell();
  if (held == null || held.currentMemberId == accountId) return;
  await cache.clear();
  await clearChatImages?.call();
}
