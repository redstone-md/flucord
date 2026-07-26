import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/guild_member_list_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/guild_member_list.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';
import 'member_profile_popover.dart';
import 'member_roster_view.dart';

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
    super.key,
  });

  final List<Member> members;
  final String spaceId;
  final String currentMemberId;
  final ValueChanged<Member> onMessage;

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
  final Map<String, LayerLink> _memberLinks = {};
  Member? _selectedMember;
  LayerLink? _selectedLink;
  bool _openUp = false;

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
    }
  }

  @override
  void dispose() {
    widget.memberList
      ?..removeListener(_onRosterChanged)
      ..clear();
    super.dispose();
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
    final visibleMembers = widget.members
        .where(
          (member) =>
              member.spaceIds.isEmpty ||
              member.spaceIds.contains(widget.spaceId),
        )
        .toList(growable: false);
    _memberLinks.removeWhere(
      (id, _) => !widget.members.any((member) => member.id == id),
    );
    final roster = widget.memberList?.list;
    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: _buildOverlay,
      child: Container(
        width: 224,
        decoration: BoxDecoration(
          color: context.surfaces.surface,
          border: Border(left: BorderSide(color: context.surfaces.border)),
        ),
        child: roster != null && roster.isLoaded
            ? _buildRoster(roster)
            : _buildCachedMembers(visibleMembers),
      ),
    );
  }

  Widget _buildRoster(GuildMemberList roster) {
    final membersById = <String, Member>{
      for (final member in widget.members) member.id: member,
    };
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
        .where((member) => member.presence != Presence.offline)
        .toList(growable: false);
    final offline = visibleMembers
        .where((member) => member.presence == Presence.offline)
        .toList(growable: false);
    final roleGroups = <String, List<Member>>{};
    for (final member in online) {
      roleGroups
          .putIfAbsent(member.roleFor(widget.spaceId), () => [])
          .add(member);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
      children: [
        for (final entry in roleGroups.entries) ...[
          MemberGroupLabel(label: entry.key, count: entry.value.length),
          for (final member in entry.value) _rowFor(member),
          const SizedBox(height: 14),
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
      role: member.roleFor(widget.spaceId),
      spaceId: widget.spaceId,
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
              canMessage: member.id != widget.currentMemberId,
              onMessage: () {
                _dismiss();
                widget.onMessage(member);
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
        : box.localToGlobal(Offset(0, box.size.height / 2)).dy;
    setState(() {
      _selectedMember = member;
      _selectedLink = link;
      _openUp = centerY > MediaQuery.sizeOf(context).height / 2;
    });
    _overlayController.show();
  }

  void _dismiss() {
    _overlayController.hide();
    if (!mounted) return;
    setState(() {
      _selectedMember = null;
      _selectedLink = null;
    });
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.role,
    required this.spaceId,
    required this.link,
    required this.selected,
    required this.onPressed,
  });

  final Member member;
  final String role;
  final String spaceId;
  final LayerLink link;
  final bool selected;
  final ValueChanged<BuildContext> onPressed;

  @override
  Widget build(BuildContext context) {
    final offline = member.presence == Presence.offline;
    return CompositedTransformTarget(
      link: link,
      child: Opacity(
        opacity: offline ? 0.58 : 1,
        child: Material(
          color: selected ? context.surfaces.raised : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: Semantics(
            button: true,
            label: 'Open profile for ${member.displayName}',
            child: InkWell(
              key: ValueKey('member-row-${member.id}'),
              onTap: () => onPressed(context),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    MemberAvatar(member: member, size: 32, spaceId: spaceId),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            role,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.surfaces.muted,
                              fontSize: 10,
                            ),
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
