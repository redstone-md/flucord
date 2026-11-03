import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'member_avatar.dart';
import 'message_preview_text.dart';

/// What a reply answers: a small avatar, the name, and the quoted text cut to
/// one line. It sits in the text column, above the name row.
class MessageReplyPreview extends StatelessWidget {
  const MessageReplyPreview({
    required this.reply,
    required this.author,
    required this.workspace,
    this.nameColor,
    this.spaceId,
    super.key,
  });

  /// The height of the reply line, from the Figma frame.
  static const height = 18.0;
  static const _avatarSize = 16.0;
  static const _gap = 4.0;

  final MessageReply reply;

  /// Who wrote the quoted message, or null when this client never met them.
  final Member? author;
  final ChatWorkspace workspace;

  /// The author's role colour here. Without one the name takes the
  /// secondary text tier.
  final Color? nameColor;

  /// The server the reply is in, for the author's server avatar.
  final String? spaceId;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final author = this.author;
    final label = FlucordTextRole.label.style;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          if (author == null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: surfaces.control,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: _avatarSize),
            )
          else
            MemberAvatar(
              member: author,
              size: _avatarSize,
              showPresence: false,
              spaceId: spaceId,
            ),
          const SizedBox(width: _gap),
          Text(
            author?.displayName ?? 'Unknown user',
            maxLines: 1,
            style: label.copyWith(
              fontWeight: FontWeight.w500,
              color: nameColor ?? surfaces.muted,
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: Text(
              reply.body.isEmpty
                  ? 'Message unavailable'
                  : messagePreviewText(context, reply.body, workspace),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: label.copyWith(color: surfaces.captionText),
            ),
          ),
        ],
      ),
    );
  }
}

/// The curved line from the author's avatar up into the reply line. It fills
/// the avatar lane beside a [MessageReplyPreview], and reaches below it, down
/// toward the avatar.
class MessageReplySpine extends StatelessWidget {
  const MessageReplySpine({
    required this.laneWidth,
    required this.avatarSize,
    super.key,
  });

  /// The avatar column and the gap after it: where the text column starts.
  final double laneWidth;
  final double avatarSize;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: laneWidth,
    height: MessageReplyPreview.height,
    child: CustomPaint(
      painter: _SpinePainter(
        color: context.surfaces.text.withValues(alpha: _SpinePainter.alpha),
        start: avatarSize / 2,
        direction: Directionality.of(context),
      ),
    ),
  );
}

/// Draws the Figma path `M 0 12 L 0 6 Q 0 0 6 0 L 26 0`, placed at the
/// avatar's centre and the middle of the reply line. Mirrored in right-to-left
/// text, where the avatar sits on the right.
class _SpinePainter extends CustomPainter {
  const _SpinePainter({
    required this.color,
    required this.start,
    required this.direction,
  });

  static const alpha = 0.16;
  static const _stroke = 1.5;
  static const _drop = 12.0;
  static const _corner = 6.0;

  /// Space between the end of the line and the reply's avatar.
  static const _endGap = 6.0;

  final Color color;

  /// Where the line rises, from the start of the lane.
  final double start;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    if (direction == TextDirection.rtl) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final y = size.height / 2;
    final path = Path()
      ..moveTo(start, y + _drop)
      ..lineTo(start, y + _corner)
      ..quadraticBezierTo(start, y, start + _corner, y)
      ..lineTo(size.width - _endGap, y);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );
  }

  @override
  bool shouldRepaint(_SpinePainter old) =>
      old.color != color || old.start != start || old.direction != direction;
}
