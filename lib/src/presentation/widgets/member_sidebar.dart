import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/guild_member_admin_controller.dart';
import '../../application/guild_member_list_controller.dart';
import '../../application/member_profile_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/guild_member_list.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'activity_views.dart';
import 'member_avatar.dart';
import 'member_profile_popover.dart';
import 'member_roster_view.dart';
import 'name_tags.dart';

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
    required this.currentMemberId,
    required this.onMessage,
    this.channelId,
    this.memberList,
    this.roles = const <CommunityRole>[],
    this.profile,
    this.onReport,
    this.onBlock,
    this.moderationBuilder,
    this.seatedByChannel = const {},
    this.nameColorOf,
    super.key,
  });

  /// Who is seated in each voice channel, keyed by channel id. A member seated
  /// in this space reads "In voice" when they are doing nothing else.
  final Map<String, List<VoiceParticipantStateEvent>> seatedByChannel;

  /// The colour of a member's top coloured role here, or null for the plain
  /// text colour.
  final int? Function(Member member)? nameColorOf;

  /// Each list starts with a group label, which carries its own space above.
  static const _listPadding = EdgeInsets.fromLTRB(8, 0, 8, 16);

  final List<Member> members;
  final String spaceId;
  final String currentMemberId;
  final ValueChanged<Member> onMessage;

  /// Drives the full profile the anchored popover fetches. Null on a host
  /// with no account behind it, which draws the identity block only.
  final MemberProfileController? profile;

  /// Opens the report flow for a member. Absent on transports with no
  /// `/reporting` access, which is what keeps the button off the popover
  /// instead of putting one there that fails.
  final ValueChanged<Member>? onReport;

  /// Blocks a member. Same reasoning as [onReport].
  final ValueChanged<Member>? onBlock;

  /// Builds the moderation controller for one member's popover, or null
  /// where this host offers no moderation: no guild-administration plane, or
  /// a surface outside a guild.
  final GuildMemberAdminController? Function(Member member)? moderationBuilder;

  /// Channel whose roster is shown. Member lists are subscribed per channel
  /// because visibility, not membership, decides who appears.
  final String? channelId;
  final GuildMemberListController? memberList;
  final List<CommunityRole> roles;

  @override
  State<MemberSidebar> createState() => _MemberSidebarState();
}

class _MemberSidebarState extends State<MemberSidebar> {
  final OverlayPortalController _overlayController = OverlayPortalController();
  final TextEditingController _search = TextEditingController();
  final Map<String, LayerLink> _memberLinks = {};
  List<Member>? _indexedMembers;
  Map<String, Member> _membersById = const {};
  Map<String, List<VoiceParticipantStateEvent>>? _indexedSeats;
  String? _seatedSpaceId;
  Set<String> _seatedIds = const {};
  Member? _selectedMember;
  LayerLink? _selectedLink;

  /// The moderation controller of the popover that is open, if the host
  /// offered one. Owned here, disposed when the popover closes.
  GuildMemberAdminController? _moderation;
  bool _openUp = false;

  /// The member search as typed. Blank restores the roster, which is what
  /// Discord does too: the results list is not a second roster to keep in
  /// sync, it is the roster put away for a moment.
  String _searchQuery = '';

  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _moderation?.dispose();
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
    if (!identical(oldWidget.members, widget.members)) {
      _memberLinks.removeWhere((id, _) => !_memberIndex.containsKey(id));
    }
    final selectedId = _selectedMember?.id;
    if (oldWidget.spaceId != widget.spaceId ||
        (selectedId != null &&
            !widget.members.any((member) => member.id == selectedId))) {
      if (_overlayController.isShowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _overlayController.hide();
        });
      }
      _selectedMember = null;
      _selectedLink = null;
      _moderation?.dispose();
      _moderation = null;
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
    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: _buildOverlay,
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: context.surfaces.surface,
          border: Border(left: BorderSide(color: context.surfaces.border)),
        ),
        child: Column(
          children: [
            _MemberSearchHeader(
              controller: _search,
              onChanged: _onSearchChanged,
            ),
            Expanded(
              child: searching
                  ? _buildSearchResults()
                  : roster != null && roster.isLoaded
                  ? _buildRoster(roster)
                  : _buildCachedMembers(_visibleMembers()),
            ),
          ],
        ),
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
        if (member.displayName.toLowerCase().startsWith(query)) member,
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

  /// Grouping the cached member table locally, used until a roster arrives.
  Widget _buildCachedMembers(List<Member> visibleMembers) {
    final online = visibleMembers
        .where((member) => member.presence.isOnline)
        .toList(growable: false);
    final offline = visibleMembers
        .where((member) => !member.presence.isOnline)
        .toList(growable: false);
    final roleGroups = <String, List<Member>>{};
    for (final member in online) {
      roleGroups
          .putIfAbsent(member.roleFor(widget.spaceId), () => [])
          .add(member);
    }
    return ListView(
      padding: MemberSidebar._listPadding,
      children: [
        for (final entry in roleGroups.entries) ...[
          MemberGroupLabel(label: entry.key, count: entry.value.length),
          for (final member in entry.value) _rowFor(member),
        ],
        if (offline.isNotEmpty) ...[
          MemberGroupLabel(label: 'Offline', count: offline.length),
          for (final member in offline) _rowFor(member),
        ],
      ],
    );
  }

  Widget _rowFor(Member member) {
    final link = _memberLinks.putIfAbsent(member.id, LayerLink.new);
    return _MemberRow(
      member: member,
      spaceId: widget.spaceId,
      inVoice: _seatedHere.contains(member.id),
      nameColor: widget.nameColorOf?.call(member),
      link: link,
      selected: member.id == _selectedMember?.id,
      onPressed: (context) => _showMember(context, member, link),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final member = _selectedMember;
    final link = _selectedLink;
    if (member == null || link == null) return const SizedBox.shrink();
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
          ),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          targetAnchor: _openUp ? Alignment.bottomLeft : Alignment.topLeft,
          followerAnchor: _openUp ? Alignment.bottomRight : Alignment.topRight,
          offset: const Offset(-8, 0),
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _dismiss();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: MemberProfilePopover(
              member: member,
              spaceId: widget.spaceId,
              profile: widget.profile,
              canMessage: member.id != widget.currentMemberId,
              moderation: _moderation,
              onMessage: () {
                _dismiss();
                widget.onMessage(member);
              },
              // Neither is offered for the account itself: Discord has no
              // "report yourself", and blocking yourself is a request the
              // server refuses.
              onReport:
                  widget.onReport == null || member.id == widget.currentMemberId
                  ? null
                  : () {
                      _dismiss();
                      widget.onReport!(member);
                    },
              onBlock:
                  widget.onBlock == null || member.id == widget.currentMemberId
                  ? null
                  : () {
                      _dismiss();
                      widget.onBlock!(member);
                    },
            ),
          ),
        ),
      ],
    );
  }

  void _showMember(BuildContext context, Member member, LayerLink link) {
    final box = context.findRenderObject() as RenderBox?;
    final centerY = box == null
        ? 0.0
        : box
              .localToGlobal(
                Offset(0, box.size.height / 2),
                ancestor: Overlay.of(context).context.findRenderObject(),
              )
              .dy;
    setState(() {
      _selectedMember = member;
      _selectedLink = link;
      _moderation?.dispose();
      _moderation = widget.moderationBuilder?.call(member);
      _openUp = centerY > MediaQuery.sizeOf(context).height / 2;
    });
    // The fetch starts with the open rather than after it, so the sections
    // arrive while the popover is already on screen.
    final profile = widget.profile;
    if (profile != null) unawaited(profile.open(member.id));
    _overlayController.show();
  }

  void _dismiss() {
    _overlayController.hide();
    if (!mounted) return;
    setState(() {
      _selectedMember = null;
      _selectedLink = null;
      _moderation?.dispose();
      _moderation = null;
    });
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
    required this.link,
    required this.selected,
    required this.onPressed,
  });

  final Member member;
  final String spaceId;
  final bool inVoice;

  /// The member's role colour as a value, or null for the plain text colour.
  final int? nameColor;
  final LayerLink link;
  final bool selected;
  final ValueChanged<BuildContext> onPressed;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final offline = !member.presence.isOnline;
    // No role line when there is nothing to show: the group label above
    // already names the role. The name then sits in the middle of the row.
    final summary = ActivitySummary.of(
      member.presenceDetail?.activities ?? const [],
      inVoice: inVoice,
    );
    final color = nameColor;
    return CompositedTransformTarget(
      link: link,
      child: Opacity(
        opacity: offline ? 0.58 : 1,
        child: Material(
          color: selected ? surfaces.raised : Colors.transparent,
          borderRadius: FlucordRadius.control,
          child: Semantics(
            button: true,
            label: 'Open profile for ${member.displayName}',
            child: InkWell(
              key: ValueKey('member-row-${member.id}'),
              onTap: () => onPressed(context),
              // Discord opens the same card from the right button. A row that
              // ignores it is a place where the mouse stops working.
              onSecondaryTap: () => onPressed(context),
              borderRadius: FlucordRadius.control,
              child: Container(
                height: MemberRosterView.rowHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    MemberAvatar(
                      member: member,
                      size: 28,
                      spaceId: spaceId,
                      presenceBorderColor: surfaces.surface,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  member.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: FlucordTextRole.label.style.copyWith(
                                    color: color == null
                                        ? surfaces.text
                                        : Color(color),
                                  ),
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
