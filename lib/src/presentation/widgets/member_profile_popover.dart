import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';

class MemberProfilePopover extends StatelessWidget {
  const MemberProfilePopover({
    required this.member,
    required this.spaceId,
    required this.canMessage,
    required this.onMessage,
    super.key,
  });

  final Member member;
  final String spaceId;
  final bool canMessage;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) => Semantics(
    scopesRoute: true,
    namesRoute: true,
    explicitChildNodes: true,
    label: '${member.displayName} profile',
    child: Material(
      key: const ValueKey('member-profile-popover'),
      color: context.surfaces.raised,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: context.surfaces.border),
      ),
      child: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(height: 68, color: Color(member.colorValue)),
                Positioned(
                  left: 16,
                  top: 38,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: context.surfaces.raised,
                        width: 5,
                      ),
                    ),
                    child: MemberAvatar(
                      member: member,
                      spaceId: spaceId,
                      size: 64,
                      presenceBorderColor: context.surfaces.raised,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    member.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _presenceLabel(member.presence),
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ProfileLabel(label: 'ROLE'),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: context.surfaces.inset,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Color(member.colorValue),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              member.roleFor(spaceId),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ProfileLabel(label: 'USER ID'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          member.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.surfaces.muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      _CopyMemberIdButton(memberId: member.id),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: const ValueKey('message-member'),
                    onPressed: canMessage ? onMessage : null,
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('Message'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static String _presenceLabel(Presence presence) => switch (presence) {
    Presence.online => 'Online',
    Presence.idle => 'Idle',
    Presence.offline => 'Offline',
  };
}

class _CopyMemberIdButton extends StatefulWidget {
  const _CopyMemberIdButton({required this.memberId});

  final String memberId;

  @override
  State<_CopyMemberIdButton> createState() => _CopyMemberIdButtonState();
}

class _CopyMemberIdButtonState extends State<_CopyMemberIdButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('copy-member-id'),
    onPressed: _copy,
    tooltip: _copied ? 'User ID copied' : 'Copy user ID',
    visualDensity: VisualDensity.compact,
    icon: Icon(_copied ? Icons.check : Icons.copy_outlined, size: 16),
  );

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.memberId));
    if (mounted) setState(() => _copied = true);
  }
}

class _ProfileLabel extends StatelessWidget {
  const _ProfileLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: context.surfaces.muted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    ),
  );
}
