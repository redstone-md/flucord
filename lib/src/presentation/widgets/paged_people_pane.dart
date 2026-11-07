import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'member_avatar.dart';

/// One row of a [PagedPeoplePane]: the person, and what the row shows after
/// their name, if anything.
typedef PagedPerson = ({Member member, Widget? trailing});

/// The people side of a who-reacted or who-voted dialog: the people loaded
/// so far, a bar while a page loads, and a footer that retries a failed page
/// or asks for the next one.
///
/// It holds no paging state of its own. The dialog loads the pages, because
/// each one pages differently.
class PagedPeoplePane extends StatelessWidget {
  const PagedPeoplePane({
    required this.people,
    required this.loading,
    required this.failed,
    required this.hasMore,
    required this.emptyLabel,
    required this.loadingLabel,
    required this.failureLabel,
    required this.onRetry,
    required this.onLoadMore,
    required this.loadMoreKey,
    this.header,
    super.key,
  });

  final List<PagedPerson> people;
  final bool loading;

  /// The last page failed to load. The footer offers [onRetry].
  final bool failed;

  /// More people are behind the last page. The footer offers [onLoadMore].
  final bool hasMore;

  /// What the empty list says when nothing is loading, and while it is.
  final String emptyLabel;
  final String loadingLabel;
  final String failureLabel;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final Key loadMoreKey;

  /// Drawn above the list, such as what the people reacted with.
  final Widget? header;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ?header,
      if (loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: people.isEmpty
            ? Center(
                child: Text(
                  loading ? loadingLabel : emptyLabel,
                  style: TextStyle(
                    fontSize: FlucordType.caption,
                    color: context.surfaces.muted,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: people.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  indent: 48,
                  color: context.surfaces.border.withValues(alpha: 0.7),
                ),
                itemBuilder: (context, index) => _row(context, people[index]),
              ),
      ),
      if (failed)
        _footer(
          context,
          children: [
            FlucordIcon(
              FlucordIcons.error,
              size: 15,
              color: context.surfaces.errorText,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                failureLabel,
                style: const TextStyle(fontSize: FlucordType.caption),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        )
      else if (hasMore)
        _footer(
          context,
          children: [
            TextButton(
              key: loadMoreKey,
              onPressed: loading ? null : onLoadMore,
              child: const Text('Load more'),
            ),
          ],
        ),
    ],
  );

  Widget _row(BuildContext context, PagedPerson person) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    child: Row(
      children: [
        MemberAvatar(member: person.member, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            person.member.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: FlucordType.caption,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ?person.trailing,
      ],
    ),
  );

  Widget _footer(BuildContext context, {required List<Widget> children}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.surfaces.border)),
        ),
        child: Row(children: children),
      );
}
