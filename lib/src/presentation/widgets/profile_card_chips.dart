part of 'profile_card.dart';

/// The "+N" chip after a row cut short, and the chip that folds the row
/// back once it is open. The badges and the roles both use it, and both open
/// in place.
class _MoreChip extends StatelessWidget {
  const _MoreChip({
    required this.hidden,
    required this.expanded,
    required this.noun,
    required this.height,
    required this.onToggle,
    super.key,
  });

  static const _padding = 6.0;

  /// How many items the folded row leaves out.
  final int hidden;
  final bool expanded;

  /// What the row holds, such as "roles", for the tooltip.
  final String noun;
  final double height;
  final VoidCallback onToggle;

  /// The folded chip's width for [hidden], as it will lay out.
  static double widthOf(BuildContext context, int hidden, double height) =>
      math.max(
        height,
        2 * _padding + _textWidth(context, '+$hidden', _chipTextStyle(context)),
      );

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final label = expanded ? 'Show fewer $noun' : 'Show $hidden more $noun';
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        expanded: expanded,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: surfaces.quietFill,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onToggle,
            child: Container(
              height: height,
              constraints: BoxConstraints(minWidth: height),
              padding: const EdgeInsets.symmetric(horizontal: _padding),
              child: Center(
                widthFactor: 1,
                child: expanded
                    ? FlucordIcon(
                        FlucordIcons.chevronUp,
                        size: 12,
                        color: surfaces.bodyText,
                      )
                    : Text('+$hidden', style: _chipTextStyle(context)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The text of a role chip and of the "+N" chip.
TextStyle _chipTextStyle(BuildContext context) =>
    FlucordTextRole.caption.style.copyWith(color: context.surfaces.bodyText);

/// The width [text] takes in [style] here, rounded up so a row measured
/// with it never comes out narrower than the row laid out.
double _textWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

/// How many of [widths], in order, fit in [runs] runs of [maxWidth] when
/// the items [trailing] gives for the rest left out come after them. Runs
/// break the way [Wrap] breaks them.
int _leadingThatFit(
  List<double> widths, {
  required double maxWidth,
  required double spacing,
  required int runs,
  required List<double> Function(int hidden) trailing,
}) {
  bool fits(Iterable<double> items) {
    var run = 0;
    double? end;
    for (final item in items) {
      final width = math.min(item, maxWidth);
      if (end == null || end + spacing + width > maxWidth) {
        run++;
        end = width;
      } else {
        end += spacing + width;
      }
      if (run > runs) return false;
    }
    return true;
  }

  for (var shown = widths.length; shown > 0; shown--) {
    if (fits([...widths.take(shown), ...trailing(widths.length - shown)])) {
      return shown;
    }
  }
  return 0;
}

/// The first few badges, then "+N", which shows the rest in place.
class _Badges extends StatefulWidget {
  const _Badges({required this.badges});

  final List<ProfileBadge> badges;

  @override
  State<_Badges> createState() => _BadgesState();
}

class _BadgesState extends State<_Badges> {
  static const _shown = 3;
  static const _size = 22.0;

  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final badges = widget.badges;
    final hidden = badges.length - _shown;
    return Wrap(
      key: const ValueKey('profile-card-badges'),
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final badge in _expanded ? badges : badges.take(_shown))
          Tooltip(
            message: badge.description,
            child: Container(
              height: _size,
              width: _size,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: context.surfaces.quietFill,
                borderRadius: FlucordRadius.full,
              ),
              child: RemoteIdentityImage(
                url: DiscordCdn.badgeIcon(badge.icon),
                fallback: const SizedBox.shrink(),
              ),
            ),
          ),
        if (hidden > 0)
          _MoreChip(
            key: const ValueKey('profile-card-more-badges'),
            hidden: hidden,
            expanded: _expanded,
            noun: 'badges',
            height: _size,
            onToggle: () => setState(() => _expanded = !_expanded),
          ),
      ],
    );
  }
}

/// The roles held here as chips with their colour, and "+" for someone who
/// can hand out roles. A role in [removable] can be taken away from the
/// chip.
///
/// Where [folds], the chips that do not fit in two rows hide behind "+N".
class _Roles extends StatefulWidget {
  const _Roles({
    required this.roles,
    required this.addable,
    this.onAdd,
    this.removable = const {},
    this.onRemove,
    this.folds = true,
  });

  static const _runs = 2;
  static const _spacing = 4.0;
  static const _addSize = 20.0;

  final List<CommunityRole> roles;
  final List<CommunityRole> addable;
  final ValueChanged<CommunityRole>? onAdd;

  /// The ids of the roles [onRemove] may take away.
  final Set<String> removable;
  final ValueChanged<CommunityRole>? onRemove;
  final bool folds;

  @override
  State<_Roles> createState() => _RolesState();
}

class _RolesState extends State<_Roles> {
  var _expanded = false;

  Future<void> _pick(BuildContext context) async {
    final role = await showMenu<CommunityRole>(
      context: context,
      position: menuBelow(context),
      items: [
        if (widget.addable.isEmpty)
          const FlucordMenuItem(label: 'No roles to add', enabled: false),
        for (final role in widget.addable)
          FlucordMenuItem(
            key: ValueKey('profile-card-role-choice-${role.id}'),
            value: role,
            label: role.name,
            leading: _RoleDot(colorValue: role.colorValue),
          ),
      ],
    );
    if (role != null) widget.onAdd?.call(role);
  }

  /// How many roles show while folded, given the row's [maxWidth].
  int _foldedCount(BuildContext context, double maxWidth) {
    final roles = widget.roles;
    final add = widget.onAdd == null ? null : _Roles._addSize;
    return _leadingThatFit(
      [for (final role in roles) _RoleChip.widthOf(context, role.name)],
      maxWidth: maxWidth,
      spacing: _Roles._spacing,
      runs: _Roles._runs,
      trailing: (hidden) => [
        if (hidden > 0) _MoreChip.widthOf(context, hidden, _RoleChip.height),
        ?add,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final roles = widget.roles;
    final remove = widget.onRemove;
    final add = widget.onAdd;
    Widget chips(int shown, {required bool foldable}) => Wrap(
      spacing: _Roles._spacing,
      runSpacing: _Roles._spacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final role in roles.take(shown))
          _RoleChip(
            key: ValueKey('profile-card-role-${role.id}'),
            role: role,
            onRemove: remove != null && widget.removable.contains(role.id)
                ? () => remove(role)
                : null,
          ),
        if (foldable)
          _MoreChip(
            key: const ValueKey('profile-card-more-roles'),
            hidden: roles.length - shown,
            expanded: _expanded,
            noun: 'roles',
            height: _RoleChip.height,
            onToggle: () => setState(() => _expanded = !_expanded),
          ),
        if (add != null)
          Builder(
            builder: (context) => FlucordIconButton(
              key: const ValueKey('profile-card-add-role'),
              icon: FlucordIcons.add,
              tooltip: 'Add role',
              dimension: _Roles._addSize,
              borderRadius: FlucordRadius.full,
              onPressed: () => _pick(context),
            ),
          ),
      ],
    );
    return Column(
      key: const ValueKey('profile-card-roles'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Roles',
          style: FlucordTextRole.caption.style.copyWith(color: surfaces.muted),
        ),
        const SizedBox(height: 6),
        if (!widget.folds)
          chips(roles.length, foldable: false)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final folded = _foldedCount(context, constraints.maxWidth);
              final foldable = folded < roles.length;
              return chips(
                foldable && !_expanded ? folded : roles.length,
                foldable: foldable,
              );
            },
          ),
      ],
    );
  }
}

/// One role: its colour dot and its name. With [onRemove], the dot turns
/// into an "x" while the chip is hovered or the "x" has focus, as Discord
/// draws it, and a click on it takes the role away.
class _RoleChip extends StatefulWidget {
  const _RoleChip({required this.role, this.onRemove, super.key});

  static const height = 20.0;
  static const _start = 6.0;
  static const _mark = 12.0;
  static const _gap = 4.0;
  static const _end = 8.0;

  final CommunityRole role;
  final VoidCallback? onRemove;

  /// The chip's width for a role called [name], as it will lay out.
  static double widthOf(BuildContext context, String name) =>
      _start +
      _mark +
      _gap +
      _textWidth(context, name, _chipTextStyle(context)) +
      _end;

  @override
  State<_RoleChip> createState() => _RoleChipState();
}

class _RoleChipState extends State<_RoleChip> {
  var _hovered = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final role = widget.role;
    final dot = _RoleDot(colorValue: role.colorValue);
    final remove = widget.onRemove;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: _RoleChip.height,
        padding: const EdgeInsetsDirectional.only(
          start: _RoleChip._start,
          end: _RoleChip._end,
        ),
        decoration: BoxDecoration(
          color: surfaces.quietFill,
          borderRadius: FlucordRadius.full,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: _RoleChip._gap,
          children: [
            SizedBox.square(
              dimension: _RoleChip._mark,
              child: remove == null
                  ? Center(child: dot)
                  : Semantics(
                      button: true,
                      label: 'Remove role ${role.name}',
                      excludeSemantics: true,
                      child: InkWell(
                        key: ValueKey('profile-card-role-remove-${role.id}'),
                        onTap: remove,
                        onFocusChange: (focused) =>
                            setState(() => _focused = focused),
                        customBorder: const CircleBorder(),
                        child: Center(
                          child: _hovered || _focused
                              ? FlucordIcon(
                                  FlucordIcons.clear,
                                  size: _RoleChip._mark,
                                  color: surfaces.text,
                                )
                              : dot,
                        ),
                      ),
                    ),
            ),
            Flexible(
              child: Text(
                role.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _chipTextStyle(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A role's colour dot. A role with no colour takes the muted grey, which is
/// how Discord draws one.
class _RoleDot extends StatelessWidget {
  const _RoleDot({this.colorValue});

  final int? colorValue;

  @override
  Widget build(BuildContext context) {
    final value = colorValue;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: value == null ? context.surfaces.muted : Color(value),
        shape: BoxShape.circle,
      ),
      child: const SizedBox.square(dimension: 8),
    );
  }
}
