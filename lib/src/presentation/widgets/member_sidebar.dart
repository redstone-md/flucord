import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_member_list_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/guild_member_list.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'activity_views.dart';
import 'member_avatar.dart';
import 'member_roster_view.dart';
import 'display_name.dart';
import 'motion_scope.dart';
import 'name_tags.dart';
import 'nameplate_backdrop.dart';
import 'popup_anchor.dart';
import 'presence_scope.dart';
import 'profile_card_route.dart';

/// The right-hand member panel.
///
/// The roster it renders is server-authoritative: Discord decides the groups,
/// their order and their counts, and only sends the rows a client has
/// subscribed to. Local grouping is kept only as the pre-roster fallback,
/// because the cached member table is all a transport without lazy member
/// lists — or a channel whose first page has not landed — can offer.
class MemberSidebar extends StatefulWidget {
  const MemberSidebar({
    required this.members,
    required this.spaceId,
    this.cardFor,
    this.channelId,
    this.memberList,
    this.roles = const <CommunityRole>[],
    this.seatedByChannel = const {},
    this.heldRolesOf,
    super.key,
  });

  /// Who is seated in each voice channel, keyed by channel id. A member seated
  /// in this space reads "In voice" when they are doing nothing else.
  final Map<String, List<VoiceParticipantStateEvent>> seatedByChannel;

  /// The roles a member holds here, which colour their name, group them while
  /// no roster has arrived, and name their role in the popover. Null on a host
  /// with no roles to read.
  final HeldRoles Function(Member member)? heldRolesOf;

  /// Each list starts with a group label, which carries its own space above.
  static const _listPadding = EdgeInsets.fromLTRB(8, 0, 8, 16);

  final List<Member> members;
  final String spaceId;

  /// Builds the profile card a row opens beside itself; `close` closes it.
  /// Null opens nothing.
  final Widget Function(Member member, VoidCallback close)? cardFor;

  /// Channel whose roster is shown. Member lists are subscribed per channel
  /// because visibility, not membership, decides who appears.
  final String? channelId;
  final GuildMemberListController? memberList;
  final List<CommunityRole> roles;

  @override
  State<MemberSidebar> createState() => _MemberSidebarState();
}

class _MemberSidebarState extends State<MemberSidebar> {
  final TextEditingController _search = TextEditingController();
  List<Member>? _indexedMembers;
  Map<String, Member> _membersById = const {};
  Map<String, List<VoiceParticipantStateEvent>>? _indexedSeats;
  String? _seatedSpaceId;
  Set<String> _seatedIds = const {};

  /// Whose card is open, and what closes it.
  String? _openMemberId;
  VoidCallback? _closeCard;

  /// The member search as typed. Blank restores the roster, which is what
  /// Discord does too: the results list is not a second roster to keep in
  /// sync, it is the roster put away for a moment.
  String _searchQuery = '';

  Timer? _searchDebounce;

  @override
  void dispose() {
    // A card left open would point at a row that is gone. Not during the
    // build: closing pops a route.
    if (_closeCard case final close?) {
      WidgetsBinding.instance.addPostFrameCallback((_) => close());
    }
    _searchDebounce?.cancel();
    _search.dispose();
    widget.memberList
      ?..removeListener(_onRosterChanged)
      ..clear();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.memberList?.addListener(_onRosterChanged);
    _watchChannel();
  }

  @override
  void didUpdateWidget(covariant MemberSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memberList != widget.memberList) {
      oldWidget.memberList?.removeListener(_onRosterChanged);
      widget.memberList?.addListener(_onRosterChanged);
    }
    if (oldWidget.spaceId != widget.spaceId ||
        oldWidget.channelId != widget.channelId ||
        oldWidget.memberList != widget.memberList) {
      _watchChannel();
    }
    final openId = _openMemberId;
    final close = _closeCard;
    if (openId != null &&
        close != null &&
        (oldWidget.spaceId != widget.spaceId ||
            !_memberIndex.containsKey(openId))) {
      // Not during the build: closing pops a route.
      WidgetsBinding.instance.addPostFrameCallback((_) => close());
    }
  }

  void _watchChannel() => widget.memberList?.viewChannel(
    guildId: widget.spaceId,
    channelId: widget.channelId,
  );

  void _onRosterChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final roster = widget.memberList?.list;
    final searching = _searchQuery.trim().isNotEmpty;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border(left: BorderSide(color: context.surfaces.border)),
      ),
      child: Column(
        children: [
          _MemberSearchHeader(controller: _search, onChanged: _onSearchChanged),
          Expanded(
            child: searching
                ? _buildSearchResults()
                : roster != null && roster.isLoaded
                ? _buildRoster(roster)
                : _buildCachedMembers(_visibleMembers()),
          ),
        ],
      ),
    );
  }

  /// Reports the query once typing has settled, and renders results right
  /// away: the local table is what a small guild already holds, and what the
  /// chunk route adds arrives as an ordinary member update.
  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchDebounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    // Discord's own search field asks as you type; the debounce keeps one
    // keystroke from spending one socket ask.
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      widget.memberList?.searchMembers(trimmed);
    });
  }

  /// The members of this space whose name matches the query.
  ///
  /// A starts-with match, because that is the question the chunk route
  /// answers too: a search that showed "Ver" for "Dover" here would disagree
  /// with the members the route then delivers.
  List<Member> _matchingMembers() {
    final query = _searchQuery.trim().toLowerCase();
    return [
      for (final member in _visibleMembers())
        if (member
            .displayNameFor(widget.spaceId)
            .toLowerCase()
            .startsWith(query))
          member,
    ];
  }

  Widget _buildSearchResults() {
    final results = _matchingMembers();
    if (results.isEmpty) {
      return ListView(
        padding: MemberSidebar._listPadding,
        children: [
          const MemberGroupLabel(label: 'Members', count: 0),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Nobody by that name yet.',
              style: FlucordTextRole.caption.style.copyWith(
                color: context.surfaces.muted,
              ),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: MemberSidebar._listPadding,
      children: [
        MemberGroupLabel(label: 'Members', count: results.length),
        for (final member in results) _rowFor(member),
      ],
    );
  }

  /// The cached members this space can show, walked only when the roster is
  /// missing and the cached list is what actually gets rendered.
  List<Member> _visibleMembers() => widget.members
      .where(
        (member) =>
            member.spaceIds.isEmpty || member.spaceIds.contains(widget.spaceId),
      )
      .toList(growable: false);

  /// The member table keyed by id, rebuilt only when the table itself changes.
  ///
  /// The roster asks for a member per row it draws and the panel redraws with
  /// the shell, so keying the table per draw cost a pass over every member the
  /// client holds on every frame.
  Map<String, Member> get _memberIndex {
    if (!identical(_indexedMembers, widget.members)) {
      _indexedMembers = widget.members;
      _membersById = {for (final member in widget.members) member.id: member};
    }
    return _membersById;
  }

  /// The ids of members seated in a voice channel of this space. Rebuilt
  /// only when the seats or the space change: the seat map is replaced, not
  /// edited, on every change.
  Set<String> get _seatedHere {
    final seats = widget.seatedByChannel;
    if (!identical(_indexedSeats, seats) || _seatedSpaceId != widget.spaceId) {
      _indexedSeats = seats;
      _seatedSpaceId = widget.spaceId;
      _seatedIds = {
        for (final channel in seats.values)
          for (final seat in channel)
            if (seat.guildId == widget.spaceId) seat.userId,
      };
    }
    return _seatedIds;
  }

  Widget _buildRoster(GuildMemberList roster) {
    final membersById = _memberIndex;
    return MemberRosterView(
      list: roster,
      memberOf: (userId) => membersById[userId],
      roleNames: {
        for (final role in widget.roles)
          if (role.spaceId == widget.spaceId) role.id: role.name,
      },
      memberRowBuilder: _rowFor,
      onViewportChanged:
          ({
            required double scrollOffset,
            required double viewportHeight,
            required double rowHeight,
          }) => widget.memberList?.updateViewport(
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            rowHeight: rowHeight,
          ),
    );
  }

  HeldRoles _rolesOf(Member member) =>
      widget.heldRolesOf?.call(member) ?? HeldRoles.none;

  /// Grouping the cached member table locally, used until a roster arrives.
  ///
  /// As Discord does: an online member goes under their highest hoisted role,
  /// the groups in the roles' order, and one with no hoisted role under
  /// Online.
  Widget _buildCachedMembers(List<Member> visibleMembers) {
    bool online(Member member) => PresenceScope.isOnline(context, member);
    final offline = visibleMembers
        .where((member) => !online(member))
        .toList(growable: false);
    final roleGroups = <CommunityRole, List<Member>>{};
    final ungrouped = <Member>[];
    for (final member in visibleMembers) {
      if (!online(member)) continue;
      final hoisted = _rolesOf(member).hoisted;
      if (hoisted == null) {
        ungrouped.add(member);
      } else {
        roleGroups.putIfAbsent(hoisted, () => []).add(member);
      }
    }
    final groups = roleGroups.entries.toList(growable: false)
      ..sort((left, right) => CommunityRole.highestFirst(left.key, right.key));
    return ListView(
      padding: MemberSidebar._listPadding,
      children: [
        for (final MapEntry(key: role, value: members) in groups) ...[
          MemberGroupLabel(label: role.name, count: members.length),
          for (final member in members) _rowFor(member),
        ],
        if (ungrouped.isNotEmpty) ...[
          MemberGroupLabel(label: 'Online', count: ungrouped.length),
          for (final member in ungrouped) _rowFor(member),
        ],
        if (offline.isNotEmpty) ...[
          MemberGroupLabel(label: 'Offline', count: offline.length),
          for (final member in offline) _rowFor(member),
        ],
      ],
    );
  }

  Widget _rowFor(Member member) => _MemberRow(
    member: member,
    spaceId: widget.spaceId,
    inVoice: _seatedHere.contains(member.id),
    nameColor: _rolesOf(member).nameColor,
    selected: member.id == _openMemberId,
    onPressed: (context) => unawaited(_showMember(context, member)),
  );

  /// Opens [member]'s card beside the row at [rowContext].
  Future<void> _showMember(BuildContext rowContext, Member member) async {
    final cardFor = widget.cardFor;
    if (cardFor == null) return;
    setState(() => _openMemberId = member.id);
    await showProfileCard(
      context: rowContext,
      anchor: popupAnchorOf(rowContext),
      builder: (close) {
        _closeCard = close;
        return cardFor(member, close);
      },
    );
    _closeCard = null;
    if (mounted) setState(() => _openMemberId = null);
  }
}

/// The 48 px header with the recessed "Search members" field.
class _MemberSearchHeader extends StatelessWidget {
  const _MemberSearchHeader({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    OutlineInputBorder outline(Color color, double width) => OutlineInputBorder(
      borderRadius: FlucordRadius.control,
      borderSide: BorderSide(color: color, width: width),
    );
    final rest = outline(surfaces.border, 1);
    return Container(
      key: const ValueKey('member-list-header'),
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: surfaces.border)),
      ),
      child: TextField(
        key: const ValueKey('member-search'),
        controller: controller,
        onChanged: onChanged,
        style: FlucordTextRole.label.style.copyWith(color: surfaces.text),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: surfaces.inset,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          prefixIcon: FlucordIcon(
            FlucordIcons.search,
            size: 16,
            color: surfaces.captionText,
          ),
          prefixIconConstraints: const BoxConstraints.tightFor(width: 32),
          hintText: 'Search members',
          hintStyle: FlucordTextRole.caption.style.copyWith(
            color: surfaces.captionText,
          ),
          border: rest,
          enabledBorder: rest,
          focusedBorder: outline(surfaces.focusRing, 2),
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.spaceId,
    required this.inVoice,
    required this.nameColor,
    required this.selected,
    required this.onPressed,
  });

  final Member member;
  final String spaceId;
  final bool inVoice;

  /// The member's role colour as a value, or null for the plain text colour.
  final int? nameColor;
  final bool selected;
  final ValueChanged<BuildContext> onPressed;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final live = PresenceScope.memberOf(context, member);
    final offline = !live.presence.isOnline;
    // No role line when there is nothing to show: the group label above
    // already names the role. The name then sits in the middle of the row.
    final summary = ActivitySummary.of(
      live.presenceDetail?.activities ?? const [],
      inVoice: inVoice,
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          MemberAvatar(
            member: member,
            size: 28,
            spaceId: spaceId,
            decorated: true,
            presenceBorderColor: surfaces.surface,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: NameplateText(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: DisplayName(
                          member.displayNameFor(spaceId),
                          style: FlucordTextRole.label.style.copyWith(
                            color: surfaces.text,
                          ),
                          nameStyle: member.tags.nameStyle,
                          inServer: InServer(roleColor: nameColor),
                        ),
                      ),
                      NameTags(member: member),
                    ],
                  ),
                  if (summary != null)
                    ActivitySummaryLine(
                      key: ValueKey('member-activity-${member.id}'),
                      summary: summary,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return Opacity(
      opacity: offline ? 0.58 : 1,
      child: Material(
        color: selected ? surfaces.raised : Colors.transparent,
        borderRadius: FlucordRadius.control,
        child: Semantics(
          button: true,
          label: 'Open profile for ${member.displayNameFor(spaceId)}',
          child: InkWell(
            key: ValueKey('member-row-${member.id}'),
            onTap: () => onPressed(context),
            // Discord opens the same card from the right button. A row that
            // ignores it is a place where the mouse stops working.
            onSecondaryTap: () => onPressed(context),
            borderRadius: FlucordRadius.control,
            child: SizedBox(
              height: MemberRosterView.rowExtentOf(context),
              child: MotionHoverRegion(
                child: WithNameplate(
                  nameplate: member.tags.nameplate,
                  placement: NameplatePlacement.memberList,
                  selected: selected,
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
