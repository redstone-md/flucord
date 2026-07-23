import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';
import 'member_profile_popover.dart';

class MemberSidebar extends StatefulWidget {
  const MemberSidebar({
    required this.members,
    required this.spaceId,
    required this.currentMemberId,
    required this.onMessage,
    super.key,
  });

  final List<Member> members;
  final String spaceId;
  final String currentMemberId;
  final ValueChanged<Member> onMessage;

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
  void didUpdateWidget(covariant MemberSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedId = _selectedMember?.id;
    if (oldWidget.spaceId != widget.spaceId ||
        (selectedId != null &&
            !widget.members.any((member) => member.id == selectedId))) {
      _overlayController.hide();
      _selectedMember = null;
      _selectedLink = null;
    }
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
    _memberLinks.removeWhere(
      (id, _) => !visibleMembers.any((member) => member.id == id),
    );
    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: _buildOverlay,
      child: Container(
        width: 224,
        decoration: BoxDecoration(
          color: context.surfaces.surface,
          border: Border(left: BorderSide(color: context.surfaces.border)),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
          children: [
            for (final entry in roleGroups.entries) ...[
              _MemberGroupLabel(label: entry.key, count: entry.value.length),
              for (final member in entry.value) _rowFor(member),
              const SizedBox(height: 14),
            ],
            if (offline.isNotEmpty) ...[
              _MemberGroupLabel(label: 'Offline', count: offline.length),
              for (final member in offline) _rowFor(member),
            ],
          ],
        ),
      ),
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

class _MemberGroupLabel extends StatelessWidget {
  const _MemberGroupLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 7),
      child: Text(
        '$label - $count',
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            role,
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
