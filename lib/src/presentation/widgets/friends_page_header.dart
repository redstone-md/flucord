import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_button.dart';
import 'flucord_controls.dart';

/// What the Friends page shows: one of four lists, or the Add friend view.
enum FriendsTab {
  online('Online'),
  all('All'),
  pending('Pending'),
  blocked('Blocked'),
  add('Add friend');

  const FriendsTab(this.label);

  final String label;

  /// The four lists, in the order the header offers them.
  static const lists = [online, all, pending, blocked];
}

/// The Friends page's top bar, 48 high: the page name, the four list tabs,
/// the Add friend button and, at the right end, [inbox].
///
/// Each tab is a button in the focus order, so Tab reaches it and Enter or
/// Space switches to it. The key of each is `friends-tab-<name>`.
class FriendsPageHeader extends StatelessWidget {
  const FriendsPageHeader({
    required this.selected,
    required this.onSelected,
    this.inbox,
    super.key,
  });

  static const height = 48.0;

  final FriendsTab selected;
  final ValueChanged<FriendsTab> onSelected;

  /// The inbox button, where the shell offers one.
  final Widget? inbox;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final adding = selected == FriendsTab.add;
    return Container(
      key: const ValueKey('friends-header'),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: surfaces.border)),
      ),
      child: Row(
        children: [
          // A narrow canvas scrolls the tabs rather than dropping any.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FlucordIcon(
                    FlucordIcons.friends,
                    size: 20,
                    color: surfaces.muted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Friends',
                    style: FlucordTextRole.heading.style.copyWith(
                      color: surfaces.text,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 24,
                    child: VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: surfaces.border,
                    ),
                  ),
                  const SizedBox(width: 12),
                  for (final tab in FriendsTab.lists) ...[
                    FlucordTab(
                      key: ValueKey('friends-tab-${tab.name}'),
                      label: tab.label,
                      selected: tab == selected,
                      onPressed: () => onSelected(tab),
                    ),
                    const SizedBox(width: 4),
                  ],
                  const SizedBox(width: 4),
                  // While its view is open the button reads as a selected
                  // tab, so the page says where it is.
                  Semantics(
                    selected: adding,
                    child: FlucordButton(
                      key: const ValueKey('friends-tab-add'),
                      label: FriendsTab.add.label,
                      kind: adding
                          ? FlucordButtonKind.secondary
                          : FlucordButtonKind.primary,
                      onPressed: () => onSelected(FriendsTab.add),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (inbox case final inbox?) ...[const SizedBox(width: 8), inbox],
        ],
      ),
    );
  }
}
