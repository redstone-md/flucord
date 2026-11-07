import 'chat_models.dart';

/// One page of a paged list of people, such as who reacted with an emoji or
/// who voted for a poll answer. A full page may have more behind it.
final class MemberPage {
  const MemberPage({required this.users, required this.hasMore});

  final List<Member> users;
  final bool hasMore;
}
